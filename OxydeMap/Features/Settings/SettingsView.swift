import SwiftUI
import AVFoundation
import OxydeCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    NavigationLink { ProfilesView() } label: {
                        LabeledContent("Driver profile", value: settings.allProfiles.first { $0.id == settings.value.activeProfileID }?.name ?? "Custom")
                    }
                    .accessibilityIdentifier("settings.profiles")
                }
                Section("Navigation") {
                    Picker("Map view", selection: $settings.value.cameraMode) {
                        ForEach(CameraMode.allCases) { Text($0.title).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Default zoom")
                        Slider(value: $settings.value.zoomScale, in: 0.6...1.6) { Text("Zoom") } minimumValueLabel: {
                            Image(systemName: "plus.magnifyingglass")
                        } maximumValueLabel: { Image(systemName: "minus.magnifyingglass") }
                    }
                    Toggle("Avoid tolls", isOn: $settings.value.routePreferences.avoidTolls)
                    Toggle("Avoid highways", isOn: $settings.value.routePreferences.avoidHighways)
                    Toggle("Reroute automatically", isOn: $settings.value.rerouteAutomatically)
                    Picker("Units", selection: $settings.value.units) {
                        Text("Automatic").tag(UnitSystem.automatic)
                        Text("Kilometers").tag(UnitSystem.metric)
                        Text("Miles").tag(UnitSystem.imperial)
                    }
                }
                Section("Voice") {
                    NavigationLink { VoiceSettingsView() } label: {
                        LabeledContent("Voice guidance", value: settings.value.voice.guidanceLevel.title)
                    }
                }
                Section("Appearance") {
                    NavigationLink("Map Studio") { MapStudioView() }
                    Picker("Day and night", selection: $settings.value.dayNightMode) {
                        Text("Off").tag(DayNightMode.off)
                        Text("Follow iPhone").tag(DayNightMode.system)
                        Text("Sunrise and sunset").tag(DayNightMode.sunTimes)
                    }
                    themePicker("Day theme", $settings.value.dayThemeID)
                    themePicker("Night theme", $settings.value.nightThemeID)
                    accentPicker
                    Picker("Speedometer", selection: $settings.value.speedometer) {
                        ForEach(SpeedometerStyle.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Arrival", selection: $settings.value.arrivalDisplay) {
                        Text("Arrival time").tag(ArrivalDisplay.arrivalTime)
                        Text("Time left").tag(ArrivalDisplay.timeRemaining)
                        Text("Both").tag(ArrivalDisplay.both)
                    }
                    Toggle("Haptics", isOn: $settings.value.hapticsEnabled)
                    NavigationLink("Map controls") { HUDSettingsView() }
                }
                Section("Map") {
                    Picker("Map engine", selection: $settings.value.mapEngine) {
                        ForEach(MapEngine.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(!model.configuration.vectorEngineAvailable)
                    Toggle("Live traffic", isOn: $settings.value.showsTraffic)
                    Toggle("Points of interest", isOn: $settings.value.showsPOI)
                    Picker("Label density", selection: $settings.value.labelDensity) {
                        ForEach(LabelDensity.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    if model.activeEngine == .appleMaps {
                        Text("Label density applies on the vector engine; Apple Maps manages its own labels.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Community") {
                    Toggle("Show driver reports", isOn: $settings.value.communityReportsEnabled)
                    if model.reports.allowedCategories.contains(.police) {
                        Toggle("Police reports", isOn: $settings.value.showsPoliceReports)
                    }
                    if model.reports.allowedCategories.contains(.speedCamera) {
                        Toggle("Speed camera reports", isOn: $settings.value.showsSpeedCameraReports)
                    }
                }
                Section("CarPlay") {
                    Picker("CarPlay theme", selection: Binding(get: { settings.value.carPlayThemeID ?? "" },
                                                               set: { settings.value.carPlayThemeID = $0.isEmpty ? nil : $0 })) {
                        Text("Same as iPhone").tag("")
                        ForEach(model.themes.allThemes.filter { !$0.isPremium || model.premium.isUnlocked }) { Text($0.name).tag($0.id) }
                    }
                    Text(model.carPlayConnected ? "Connected to CarPlay." : "CarPlay uses a simplified, high-contrast version of the theme.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Play") {
                    NavigationLink { GarageView() } label: {
                        LabeledContent("Garage", value: "Level \(model.play.progress.level)")
                    }
                    NavigationLink("Convoy") { ConvoyView() }
                    Toggle("Explorer mode", isOn: $settings.value.explorerEnabled)
                }
                Section {
                    NavigationLink("Privacy and Data") { PrivacySettingsView() }
                    NavigationLink("Trips") { TripDashboardView() }
                    NavigationLink("Oxyde Premium") { PremiumView() }
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                        .accessibilityIdentifier("settings.diagnostics")
                }
                Section {
                    HStack {
                        OxydeMark(size: 36)
                        OxydeWordmark(size: 16)
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func themePicker(_ title: String, _ binding: Binding<String>) -> some View {
        Picker(title, selection: binding) {
            ForEach(model.themes.allThemes.filter { !$0.isPremium || model.premium.isUnlocked }) { Text($0.name).tag($0.id) }
        }
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accent")
            HStack(spacing: 10) {
                Button { settings.value.accentOverride = nil } label: {
                    Circle().fill(Color(hex: model.activeTheme.interface.accent)).frame(width: 30, height: 30)
                        .overlay(Text("T").font(.caption2.bold()).foregroundStyle(.black))
                        .overlay(Circle().stroke(Color.primary, lineWidth: settings.value.accentOverride == nil ? 2 : 0).padding(-3))
                }
                .accessibilityLabel("Theme accent")
                ForEach(OX.accents, id: \.name) { a in
                    Button { settings.value.accentOverride = a.hex } label: {
                        Circle().fill(Color(hex: a.hex)).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.primary, lineWidth: settings.value.accentOverride == a.hex ? 2 : 0).padding(-3))
                    }
                    .accessibilityLabel(a.name)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

extension GuidanceLevel {
    var title: String {
        switch self {
        case .full: return "All directions"
        case .alertsOnly: return "Alerts only"
        case .muted: return "Muted"
        }
    }
}

struct VoiceSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = settings
        let voices = VoiceGuidanceManager.voices(for: settings.value.voice.language)
        Form {
            Section {
                Picker("Guidance", selection: $settings.value.voice.guidanceLevel) {
                    ForEach(GuidanceLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            Section("Voice") {
                Picker("Language", selection: Binding(get: { settings.value.voice.language ?? "" },
                                                      set: { settings.value.voice.language = $0.isEmpty ? nil : $0; settings.value.voice.voiceIdentifier = nil })) {
                    Text("Device language").tag("")
                    ForEach(VoiceGuidanceManager.availableLanguages, id: \.self) { l in
                        Text(Locale.current.localizedString(forIdentifier: l) ?? l).tag(l)
                    }
                }
                Picker("Voice", selection: Binding(get: { settings.value.voice.voiceIdentifier ?? "" },
                                                   set: { settings.value.voice.voiceIdentifier = $0.isEmpty ? nil : $0 })) {
                    Text("Automatic").tag("")
                    ForEach(voices, id: \.identifier) { v in
                        Text("\(v.name)\(v.quality == .enhanced ? " (Enhanced)" : v.quality == .premium ? " (Premium)" : "")").tag(v.identifier)
                    }
                }
                Text("Spoken directions use the turn text from Apple Maps in your device language. Distance phrases are in English in this version. Download higher-quality voices in iOS Settings > Accessibility > Spoken Content > Voices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sound") {
                VStack(alignment: .leading) {
                    Text("Volume")
                    Slider(value: $settings.value.voice.volume, in: 0.1...1)
                }
                VStack(alignment: .leading) {
                    Text("Speaking rate")
                    Slider(value: $settings.value.voice.rate, in: 0.8...1.2)
                }
                Toggle("Lower music while speaking", isOn: $settings.value.voice.duckOtherAudio)
                Toggle("Pause podcasts and audiobooks", isOn: $settings.value.voice.pauseSpokenAudio)
                Button("Play Sample") {
                    model.voice.settings = settings.value.voice
                    let d = DistanceFormatter.guidance(meters: 400, system: settings.value.resolvedUnits).spoken
                    model.voice.preview(GuidancePhrasebook.localized.inDistance(d, "Turn right"))
                }
            }
        }
        .navigationTitle("Voice Guidance")
    }
}

struct HUDSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    private let names: [HUDElement: String] = [
        .speedometer: "Speedometer", .compass: "Compass", .layersButton: "Layers button", .reportButton: "Report button",
        .soundButton: "Sound button", .studioButton: "Map Studio button", .quickAccess: "Quick access bar", .trafficLegend: "Traffic legend",
    ]

    var body: some View {
        Form {
            Section {
                ForEach(HUDElement.allCases) { e in
                    Toggle(names[e] ?? e.rawValue, isOn: Binding(
                        get: { !settings.value.hiddenElements.contains(e) },
                        set: { show in if show { settings.value.hiddenElements.remove(e) } else { settings.value.hiddenElements.insert(e) } }))
                }
            } footer: {
                Text("Hidden controls stay available in Settings. The location and clean-view buttons are always shown.")
            }
        }
        .navigationTitle("Map Controls")
    }
}

struct ProfilesView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(settings.allProfiles) { p in
                    Button { settings.apply(p) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p.symbol).frame(width: 30).foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(p.name).foregroundStyle(.primary)
                                Text(p.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.value.activeProfileID == p.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .swipeActions {
                        if !p.isBuiltIn { Button("Delete", role: .destructive) { settings.deleteProfile(p) } }
                    }
                }
            } footer: {
                Text("A profile sets themes, camera, voice, speedometer and visible controls together.")
            }
            Section {
                Button("Save Current Settings as Profile") { naming = true }
            }
        }
        .navigationTitle("Driver Profiles")
        .alert("New Profile", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                settings.saveCurrentAsProfile(named: n.isEmpty ? "My Profile" : n)
                newName = ""
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct PrivacySettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(LocationManager.self) private var location
    @State private var confirmErase = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Location") {
                LabeledContent("Access", value: permissionText)
                LabeledContent("Precise location", value: location.isPreciseAccuracy ? "On" : "Off")
                Button("Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Section {
                Toggle("Record trips", isOn: $settings.value.tripHistoryEnabled)
            } footer: {
                Text("Off by default. When on, trips are stored only on this iPhone.")
            }
            Section {
                Toggle("Sync settings with iCloud", isOn: $settings.value.cloudSyncEnabled)
                    .disabled(!model.cloudSync.isAvailable && !settings.value.cloudSyncEnabled)
                    .onChange(of: settings.value.cloudSyncEnabled) { _, on in if !on { model.cloudSync.eraseCloudCopy() } }
            } footer: {
                Text(model.cloudSync.isAvailable
                     ? "Syncs preferences and profile choices through your iCloud account. Trips, places and history are never synced."
                     : "iCloud isn't available: you're not signed in to iCloud, or this build doesn't include the iCloud capability.")
            }
            Section {
                Text("Routing, search and map tiles: Apple Maps (Apple's privacy policy applies). Traffic incidents and driver reports: the Oxyde backend, when configured, receives the map area around your route and the position of reports you submit, tagged with a random install ID that is not linked to you.")
                    .font(.footnote)
            } header: { Text("Where data goes") }
            Section {
                Button("Erase Trips, Places and History", role: .destructive) { confirmErase = true }
            }
        }
        .navigationTitle("Privacy and Data")
        .confirmationDialog("Erase all trips, saved places, saved routes and recent destinations from this iPhone?",
                            isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { model.persistence.deleteAllData() }
        }
    }

    private var permissionText: String {
        switch location.permission {
        case .notDetermined: return "Not asked yet"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .whenInUse: return "While using the app"
        case .always: return "Always"
        }
    }
}
