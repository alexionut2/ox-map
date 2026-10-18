import Foundation
import Observation
import OxydeCore

/// Group drive with friends. The driver's position is shared only while they are in a
/// convoy, only with its members, and sharing stops the moment they leave.
@MainActor
@Observable
final class ConvoyStore {
    enum State: Equatable {
        case idle
        case working
        case active(ConvoySnapshot)
        case failed(String)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private let service: ConvoyService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var lastSent: Date?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored var onJoined: (() -> Void)?

    static let colors: [HexColor] = ["#7C4DFF", "#5AD39A", "#FF7A8C", "#F2C14E", "#00D9FF", "#FF8F4A"]

    init(service: ConvoyService, settings: SettingsStore) {
        self.service = service
        self.settings = settings
    }

    var isConfigured: Bool { service.isConfigured }

    var snapshot: ConvoySnapshot? {
        if case .active(let s) = state { return s }
        return nil
    }

    /// Other members with a recent position, for the map.
    var visibleMembers: [ConvoyMember] {
        snapshot?.members.filter { !$0.isMe && $0.coordinate != nil && !$0.isStale() } ?? []
    }

    private var displayName: String {
        let n = settings.value.convoyDisplayName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Driver" : n
    }

    private var color: String {
        // Stable per install (String.hashValue changes every launch).
        Self.colors[InstallIdentity.current.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.colors.count].hexString
    }

    func create(name: String) async {
        await run { try await self.service.create(name: name, displayName: self.displayName, color: self.color) }
    }

    func join(code input: String) async {
        guard let code = ConvoyCode.normalize(input) else {
            state = .failed("Convoy codes have 6 letters and numbers.")
            return
        }
        await run { try await self.service.join(code: code, displayName: self.displayName, color: self.color) }
    }

    func shareDestination(_ place: Place) async {
        guard let code = snapshot?.code else { return }
        await run { try await self.service.setDestination(code: code, coordinate: place.coordinate, name: place.name) }
    }

    func leave() async {
        guard let code = snapshot?.code else { state = .idle; return }
        stopPolling()
        state = .idle
        try? await service.leave(code: code)
    }

    /// Sends the position at most every 5 seconds while in a convoy.
    func handle(_ fix: LocationFix) {
        guard let code = snapshot?.code, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy < 100 else { return }
        if let lastSent, Date().timeIntervalSince(lastSent) < 5 { return }
        lastSent = Date()
        Task {
            if let s = try? await service.update(code: code, coordinate: fix.coordinate,
                                                 heading: fix.hasValidCourse ? fix.course : nil),
               case .active = state {
                state = .active(s)
            }
        }
    }

    private func run(_ op: @escaping () async throws -> ConvoySnapshot) async {
        let wasActive = snapshot != nil
        state = .working
        do {
            let s = try await op()
            state = .active(s)
            if !wasActive { onJoined?() }
            startPolling()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        // Positions also arrive with our own updates; polling covers a parked phone.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let code = self.snapshot?.code, let fix = AppModel.shared.location.lastFix else { return }
                if let s = try? await self.service.update(code: code, coordinate: fix.coordinate, heading: nil),
                   case .active = self.state {
                    self.state = .active(s)
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
