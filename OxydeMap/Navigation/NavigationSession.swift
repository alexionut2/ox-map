import Foundation
import Observation
import UIKit
import OxydeCore

/// Events the CarPlay scene listens to so the car display stays in step with the phone.
enum SessionEvent {
    case routesChanged
    case started
    case progress(RouteProgress)
    case maneuverChanged
    case rerouting
    case rerouted
    case arrived
    case ended
    case alert(title: String, subtitle: String?)
}

/// Owns trip planning and active guidance. The phone UI and CarPlay both drive this one
/// object, which is what keeps route progress identical on both displays.
@MainActor
@Observable
final class NavigationSession {
    enum Phase: Equatable { case idle, planning, previewing, navigating, arrived }
    enum Signal: Equatable { case good, weak, lost }

    private(set) var phase: Phase = .idle
    /// The place whose details are showing (search result, pin, shared link).
    var selectedPlace: Place?
    private(set) var stops: [Waypoint] = []
    private(set) var routes: [Route] = []
    private(set) var selectedRouteID: UUID?
    private(set) var planningError: String?
    private(set) var progress: RouteProgress?
    private(set) var signal: Signal = .good
    private(set) var isRerouting = false
    private(set) var rerouteError: String?
    private(set) var incidentAhead: RouteIncidentMatch?
    private(set) var lastFix: LocationFix?
    private(set) var recovery: RecoverySnapshot?
    var preferences = RoutePreferences()

    @ObservationIgnored private let routing: RoutingService
    @ObservationIgnored private let location: LocationManager
    @ObservationIgnored private let voice: VoiceGuidanceManager
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let persistence: PersistenceController
    @ObservationIgnored private let traffic: TrafficStore
    @ObservationIgnored private var engine: NavigationEngine?
    @ObservationIgnored private var tripRecorder: TripRecorder?
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var etaTimer: Timer?
    @ObservationIgnored private var planTask: Task<Void, Never>?
    @ObservationIgnored private var rerouteTask: Task<Void, Never>?
    @ObservationIgnored private var lastRerouteAt: Date?
    @ObservationIgnored private var rerouteFailures = 0
    @ObservationIgnored private var lastIncidentCheck: Date?
    @ObservationIgnored private var announcedIncidentIDs: Set<String> = []
    @ObservationIgnored private var listeners: [UUID: (SessionEvent) -> Void] = [:]

    init(routing: RoutingService, location: LocationManager, voice: VoiceGuidanceManager, settings: SettingsStore,
         persistence: PersistenceController, traffic: TrafficStore) {
        self.routing = routing
        self.location = location
        self.voice = voice
        self.settings = settings
        self.persistence = persistence
        self.traffic = traffic
        preferences = settings.value.routePreferences
        recovery = RecoverySnapshot.load()
        location.onFix = { [weak self] fix in self?.handle(fix) }
    }

    var capabilities: RoutingCapabilities { routing.capabilities }
    var selectedRoute: Route? { routes.first { $0.id == selectedRouteID } ?? routes.first }
    var activeRoute: Route? { engine?.route }
    var comparisons: [RouteComparison] { RouteComparison.compare(routes) }

    var upcomingStep: RouteStep? {
        guard let r = activeRoute, let i = progress?.upcomingStepIndex, r.steps.indices.contains(i) else { return nil }
        return r.steps[i]
    }

    var followingStep: RouteStep? {
        guard let r = activeRoute, let i = progress?.followingStepIndex, r.steps.indices.contains(i) else { return nil }
        return r.steps[i]
    }

    // MARK: Listeners

    @discardableResult
    func addListener(_ handler: @escaping (SessionEvent) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = handler
        return id
    }

    func removeListener(_ id: UUID) { listeners[id] = nil }

    private func emit(_ e: SessionEvent) { listeners.values.forEach { $0(e) } }

    // MARK: Planning

    func preview(to place: Place) {
        selectedPlace = nil
        stops = [place.waypoint]
        persistence.recordRecent(place)
        calculate()
    }

    func previewSavedRoute(stops: [Waypoint], preferences: RoutePreferences) {
        self.stops = stops
        self.preferences = preferences
        calculate()
    }

    func addStop(_ place: Place) {
        // New stops go before the final destination, which is what drivers expect.
        if stops.isEmpty { stops = [place.waypoint] } else { stops.insert(place.waypoint, at: stops.count - 1) }
        if phase == .navigating {
            // Mid-trip: recalculate from here through the new stop without leaving guidance.
            lastRerouteAt = nil
            reroute()
        } else {
            calculate()
        }
    }

    func removeStop(at offsets: IndexSet) {
        stops.remove(atOffsets: offsets)
        stops.isEmpty ? cancelPlanning() : calculate()
    }

    func moveStops(from source: IndexSet, to destination: Int) {
        stops.move(fromOffsets: source, toOffset: destination)
        calculate()
    }

    func updatePreferences(_ p: RoutePreferences) {
        preferences = p
        settings.value.routePreferences = p
        if phase == .previewing || phase == .planning { calculate() }
    }

    func selectRoute(_ id: UUID) {
        selectedRouteID = id
        emit(.routesChanged)
    }

    func cancelPlanning() {
        planTask?.cancel()
        routes = []
        stops = []
        selectedRouteID = nil
        planningError = nil
        phase = .idle
        emit(.routesChanged)
    }

    func calculate() {
        planTask?.cancel()
        guard !stops.isEmpty else { return }
        phase = .planning
        planningError = nil
        planTask = Task {
            do {
                guard let fix = lastFix ?? location.lastFix else { throw RoutingError.noLocation }
                let request = RouteRequest(origin: Waypoint(name: "Current Location", coordinate: fix.coordinate),
                                           stops: stops, preferences: preferences)
                let result = try await routing.routes(for: request)
                try Task.checkCancellation()
                guard !result.isEmpty else { throw RoutingError.noRoute }
                routes = result
                selectedRouteID = result.first?.id
                phase = .previewing
                emit(.routesChanged)
            } catch is CancellationError {
                return
            } catch {
                planningError = error.localizedDescription
                routes = []
                phase = .previewing
                emit(.routesChanged)
            }
        }
    }

    // MARK: Guidance

    func start() {
        guard let route = selectedRoute else { return }
        let s = settings.value
        var scheduler = GuidanceScheduler(level: s.voice.guidanceLevel, units: s.resolvedUnits, phrasebook: .localized)
        scheduler.chainDistance = 150
        engine = NavigationEngine(route: route, scheduler: scheduler)
        routes = [route]
        selectedRouteID = route.id
        progress = nil
        signal = .good
        incidentAhead = nil
        announcedIncidentIDs = []
        rerouteFailures = 0
        voice.settings = s.voice
        phase = .navigating
        location.setMode(.navigating)
        Task { await location.requestTemporaryPreciseAccuracy() }
        UIApplication.shared.isIdleTimerDisabled = true
        if s.tripHistoryEnabled {
            tripRecorder = TripRecorder(precision: s.tripPrecision, startedAt: Date(), destinationName: route.destination?.name)
        }
        RecoverySnapshot(stops: stops, preferences: preferences, savedAt: Date()).save()
        recovery = nil
        traffic.startMonitoring(route: route)
        startTimers()
        if let fix = location.lastFix { handle(fix) }
        emit(.started)
    }

    func stop() {
        finish(arrived: false)
    }

    func resumeRecovered() {
        guard let r = recovery else { return }
        recovery = nil
        stops = r.stops
        preferences = r.preferences
        calculate()
    }

    func discardRecovery() {
        recovery = nil
        RecoverySnapshot.clear()
    }

    private func finish(arrived: Bool) {
        tickTimer?.invalidate()
        etaTimer?.invalidate()
        rerouteTask?.cancel()
        traffic.stopMonitoring()
        if let rec = tripRecorder { persistence.saveTrip(rec.finish(at: Date())) }
        tripRecorder = nil
        engine = nil
        RecoverySnapshot.clear()
        UIApplication.shared.isIdleTimerDisabled = false
        location.setMode(.browsing)
        isRerouting = false
        rerouteError = nil
        incidentAhead = nil
        if arrived {
            phase = .arrived
            emit(.arrived)
        } else {
            voice.stop()
            phase = .idle
            routes = []
            stops = []
            progress = nil
            selectedRouteID = nil
            emit(.ended)
        }
    }

    /// Clears the arrival card.
    func dismissArrival() {
        phase = .idle
        routes = []
        stops = []
        progress = nil
        selectedRouteID = nil
        emit(.ended)
    }

    private func startTimers() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        etaTimer?.invalidate()
        // Ask the provider for a fresh travel time every two minutes so the arrival time
        // follows current traffic.
        etaTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshTravelTime() }
        }
    }

    private func tick() {
        guard var e = engine else { return }
        let events = e.tick(now: Date())
        engine = e
        apply(events)
    }

    private func handle(_ fix: LocationFix) {
        lastFix = fix
        guard phase == .navigating, var e = engine else { return }
        tripRecorder?.add(fix)
        e.scheduler.level = settings.value.voice.guidanceLevel
        voice.settings = settings.value.voice
        let events = e.update(with: fix)
        engine = e
        apply(events)
        checkIncidentsAhead()
    }

    private func apply(_ events: [NavigationEvent]) {
        for event in events {
            switch event {
            case .progress(let p):
                progress = p
                emit(.progress(p))
            case .announce(let a):
                voice.speak(a)
            case .stepAdvanced:
                emit(.maneuverChanged)
            case .offRoute:
                if settings.value.rerouteAutomatically { reroute() }
            case .weakSignal:
                signal = .weak
            case .signalLost:
                signal = .lost
            case .signalRecovered:
                signal = .good
            case .arrivedAtWaypoint:
                // `stops` always holds the stops still ahead.
                if stops.count > 1 { stops.removeFirst() }
                emit(.maneuverChanged)
            case .arrived:
                finish(arrived: true)
            }
        }
    }

    // MARK: Rerouting

    func reroute() {
        guard phase == .navigating, !isRerouting, let fix = lastFix, engine != nil, !stops.isEmpty else { return }
        // Avoid hammering the routing service while the driver is still turning around.
        if let last = lastRerouteAt, Date().timeIntervalSince(last) < 8 { return }
        lastRerouteAt = Date()
        isRerouting = true
        rerouteError = nil
        emit(.rerouting)
        rerouteTask = Task {
            do {
                let request = RouteRequest(origin: Waypoint(name: "Current Location", coordinate: fix.coordinate),
                                           stops: stops,
                                           preferences: RoutePreferences(avoidTolls: preferences.avoidTolls,
                                                                         avoidHighways: preferences.avoidHighways,
                                                                         requestAlternatives: false))
                guard let newRoute = try await routing.routes(for: request).first else { throw RoutingError.noRoute }
                try Task.checkCancellation()
                guard phase == .navigating, var current = engine else { return }
                current.replaceRoute(newRoute)
                engine = current
                routes = [newRoute]
                selectedRouteID = newRoute.id
                rerouteFailures = 0
                isRerouting = false
                traffic.startMonitoring(route: newRoute)
                voice.speak(Announcement(text: current.scheduler.phrasebook.rerouted, stage: .reroute, stepIndex: nil, interrupts: false))
                emit(.rerouted)
                emit(.routesChanged)
                if let fix = lastFix { handle(fix) }
            } catch is CancellationError {
                isRerouting = false
            } catch {
                isRerouting = false
                rerouteFailures += 1
                rerouteError = error.localizedDescription
                emit(.rerouted)
                // Keep guiding along the old route and retry with backoff (5, 10, 20, 40 s).
                let delay = min(40, 5 * pow(2, Double(rerouteFailures - 1)))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                lastRerouteAt = nil
                if phase == .navigating, let p = progress, p.offset > 40 { reroute() }
            }
        }
    }

    private func refreshTravelTime() async {
        guard phase == .navigating, let e = engine, let fix = lastFix, let dest = e.route.destination,
              e.legIndex >= e.route.legEndDistances.count - 1 else { return }
        // Only on the last leg: a direct ETA request would skip intermediate stops.
        guard let seconds = try? await routing.travelTime(from: fix.coordinate, to: dest.coordinate, preferences: preferences),
              var current = engine else { return }
        current.applyTravelTimeRefresh(seconds, at: Date())
        engine = current
        progress = current.progress
        if let p = progress { emit(.progress(p)) }
    }

    // MARK: Incidents

    private func checkIncidentsAhead() {
        guard let e = engine, let p = progress else { return }
        if let last = lastIncidentCheck, Date().timeIntervalSince(last) < 10 { return }
        lastIncidentCheck = Date()
        guard let snapshot = traffic.snapshot, snapshot.freshness(at: Date()) != .stale else {
            incidentAhead = nil
            return
        }
        let matches = RouteIncidentMatcher.incidentsAhead(on: e.measuredPolyline, traveled: p.distanceTraveled,
                                                          incidents: snapshot.incidents, includeCommunity: true)
        let relevant = matches.first { $0.distanceAhead < 8000 && ($0.incident.roadClosed || $0.incident.severity >= .moderate || !$0.incident.source.isVerifiedProvider) }
        incidentAhead = relevant
        guard let m = relevant, !announcedIncidentIDs.contains(m.incident.id) else { return }
        announcedIncidentIDs.insert(m.incident.id)
        // Only provider-sourced incidents are spoken; driver reports are shown, labeled.
        if m.incident.source.isVerifiedProvider {
            let d = DistanceFormatter.guidance(meters: m.distanceAhead, system: settings.value.resolvedUnits).spoken
            voice.speak(Announcement(text: "\(m.incident.title) in \(d).", stage: .notice, stepIndex: nil, interrupts: false))
        }
        emit(.alert(title: m.incident.title, subtitle: m.incident.source.attribution))
    }

    /// Asks the provider for alternatives and returns one that avoids the incident ahead,
    /// if any does. MapKit cannot avoid a specific point, so this is a check, not a promise.
    func findRouteAvoidingIncident() async -> Route? {
        guard let m = incidentAhead, let fix = lastFix, !stops.isEmpty else { return nil }
        let request = RouteRequest(origin: Waypoint(name: "Current Location", coordinate: fix.coordinate), stops: stops,
                                   preferences: RoutePreferences(avoidTolls: preferences.avoidTolls,
                                                                 avoidHighways: preferences.avoidHighways,
                                                                 requestAlternatives: true))
        guard let candidates = try? await routing.routes(for: request) else { return nil }
        return candidates.first { r in
            RouteIncidentMatcher.incidentsAhead(on: MeasuredPolyline(r.coordinates), traveled: 0,
                                                incidents: [m.incident], includeCommunity: true).isEmpty
        }
    }

    func switchTo(_ route: Route) {
        guard phase == .navigating, var e = engine else { return }
        e.replaceRoute(route)
        engine = e
        routes = [route]
        selectedRouteID = route.id
        incidentAhead = nil
        traffic.startMonitoring(route: route)
        emit(.rerouted)
        emit(.routesChanged)
        if let fix = lastFix { handle(fix) }
    }
}

/// What is needed to resume guidance after the app was terminated mid-trip.
struct RecoverySnapshot: Codable {
    var stops: [Waypoint]
    var preferences: RoutePreferences
    var savedAt: Date

    private static let key = "oxyde.activeSession"

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    static func load() -> RecoverySnapshot? {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(RecoverySnapshot.self, from: d) else { return nil }
        // Offer to resume only recent trips.
        guard Date().timeIntervalSince(s.savedAt) < 3 * 3600, !s.stops.isEmpty else { clear(); return nil }
        return s
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
