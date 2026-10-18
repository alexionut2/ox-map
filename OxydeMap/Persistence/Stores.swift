import Foundation
import Observation
import OxydeCore

/// Owns `AppSettings`, persisting every change to UserDefaults.
@MainActor
@Observable
final class SettingsStore {
    private static let key = "oxyde.settings.v1"
    private let defaults: UserDefaults

    var value: AppSettings {
        didSet {
            guard value != oldValue else { return }
            save()
            onChange?(value)
        }
    }

    /// Profiles the user saved. Built-ins come from `DriverProfile.builtIns`.
    var customProfiles: [DriverProfile] {
        didSet { saveProfiles() }
    }

    @ObservationIgnored var onChange: ((AppSettings) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = s
        } else {
            value = AppSettings()
        }
        if let data = defaults.data(forKey: Self.key + ".profiles"),
           let p = try? JSONDecoder().decode([DriverProfile].self, from: data) {
            customProfiles = p
        } else {
            customProfiles = []
        }
        // UI tests start from a clean, known state.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingReset") {
            value = AppSettings()
            customProfiles = []
        }
    }

    var allProfiles: [DriverProfile] { DriverProfile.builtIns + customProfiles }

    func apply(_ profile: DriverProfile) { profile.apply(to: &value) }

    func saveCurrentAsProfile(named name: String) {
        customProfiles.append(DriverProfile.capture(from: value, name: name))
    }

    func deleteProfile(_ profile: DriverProfile) {
        customProfiles.removeAll { $0.id == profile.id }
        if value.activeProfileID == profile.id { value.activeProfileID = nil }
    }

    /// Replaces settings from another device during iCloud sync without echoing back.
    func replaceFromSync(_ s: AppSettings) {
        let callback = onChange
        onChange = nil
        var merged = s
        // Device-specific choices stay local.
        merged.hasCompletedOnboarding = value.hasCompletedOnboarding
        merged.cloudSyncEnabled = value.cloudSyncEnabled
        merged.tripHistoryEnabled = value.tripHistoryEnabled
        value = merged
        onChange = callback
    }

    private func save() {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.key) }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(customProfiles) { defaults.set(data, forKey: Self.key + ".profiles") }
    }
}

/// Built-in themes plus the user's custom themes, which are stored as individual
/// `.oxydetheme` files in Application Support so they can be exported as-is.
@MainActor
@Observable
final class ThemeStore {
    private(set) var customThemes: [MapTheme] = []
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.arguments.contains("-uiTestingReset") {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        load()
    }

    var allThemes: [MapTheme] { ThemeRegistry.all + customThemes }

    func theme(id: String) -> MapTheme? {
        ThemeRegistry.theme(id: id) ?? customThemes.first { $0.id == id }
    }

    func themes(in family: ThemeFamily) -> [MapTheme] {
        family == .custom ? customThemes : ThemeRegistry.themes(in: family)
    }

    func save(_ theme: MapTheme) {
        var t = theme
        if ThemeRegistry.theme(id: t.id) != nil { t = t.duplicated(named: t.name) }
        if let i = customThemes.firstIndex(where: { $0.id == t.id }) { customThemes[i] = t } else { customThemes.append(t) }
        do {
            try ThemeCodec.exportData(t).write(to: fileURL(for: t), options: .atomic)
        } catch {
            assertionFailure("Theme save failed: \(error)")
        }
    }

    func delete(_ theme: MapTheme) {
        customThemes.removeAll { $0.id == theme.id }
        try? FileManager.default.removeItem(at: fileURL(for: theme))
    }

    /// The original a custom theme was copied from, for "Restore defaults".
    func original(of theme: MapTheme) -> MapTheme? { theme.basedOn.flatMap(ThemeRegistry.theme(id:)) }

    func fileURL(for theme: MapTheme) -> URL {
        directory.appendingPathComponent(theme.id).appendingPathExtension(ThemeCodec.fileExtension)
    }

    /// A temporary, nicely named copy for sharing.
    func exportFile(for theme: MapTheme) throws -> URL {
        let safe = theme.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe.isEmpty ? "theme" : safe)
            .appendingPathExtension(ThemeCodec.fileExtension)
        try ThemeCodec.exportData(theme).write(to: url, options: .atomic)
        return url
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        customThemes = files.filter { $0.pathExtension == ThemeCodec.fileExtension }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let probe = try? JSONDecoder().decode(ThemeFileProbe.self, from: data) else { return nil }
            // Stored themes keep their ID (unlike imports).
            return probe.theme
        }.sorted { $0.name < $1.name }
    }

    private struct ThemeFileProbe: Decodable { var theme: MapTheme }
}

/// A random identifier for this installation, used only for backend rate limiting and
/// vote de-duplication. Not derived from the device or the user.
enum InstallIdentity {
    static var current: String {
        let key = "oxyde.installID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

/// Mirrors settings to iCloud key-value storage when — and only when — the user turned
/// sync on and the build has the iCloud key-value entitlement.
@MainActor
final class CloudSettingsSync {
    private let key = "oxyde.settings.v1"
    private weak var settings: SettingsStore?
    private var observer: NSObjectProtocol?

    var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    func attach(to settings: SettingsStore) {
        self.settings = settings
        let previous = settings.onChange
        settings.onChange = { [weak self] s in
            previous?(s)
            self?.push(s)
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pull() }
            }
        if settings.value.cloudSyncEnabled { pull() }
    }

    private func push(_ s: AppSettings) {
        guard s.cloudSyncEnabled, isAvailable, let data = try? JSONEncoder().encode(s) else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: key)
    }

    private func pull() {
        guard let settings, settings.value.cloudSyncEnabled, isAvailable else { return }
        NSUbiquitousKeyValueStore.default.synchronize()
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: key),
              let remote = try? JSONDecoder().decode(AppSettings.self, from: data), remote != settings.value else { return }
        settings.replaceFromSync(remote)
    }

    /// Removes the synced copy when the user turns sync off.
    func eraseCloudCopy() {
        NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
    }
}
