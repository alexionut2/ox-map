import Foundation
import Observation
import OxydeCore

/// Fetches incidents for the area around the route or the visible map, with polling
/// during navigation and backoff on failures. Holds the fetch time so the UI can show
/// how fresh the data is.
@MainActor
@Observable
final class TrafficStore {
    private(set) var snapshot: IncidentSnapshot?
    private(set) var lastError: APIError?
    private(set) var isLoading = false

    @ObservationIgnored let service: IncidentService
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastBrowseFetch: (area: BoundingBox, at: Date)?

    init(service: IncidentService) { self.service = service }

    var isConfigured: Bool { service.isConfigured }

    /// Incidents to draw: hidden when stale, and filtered by the user's report settings.
    func visibleIncidents(settings: AppSettings, now: Date = Date()) -> [Incident] {
        guard let s = snapshot, s.freshness(at: now) != .stale else { return [] }
        return s.incidents.filter { inc in
            if !inc.source.isVerifiedProvider && !settings.communityReportsEnabled { return false }
            if inc.kind == .police && !settings.showsPoliceReports { return false }
            if inc.kind == .speedCamera && !settings.showsSpeedCameraReports { return false }
            if let r = inc.report, r.isExpired(at: now) { return false }
            return true
        }
    }

    func startMonitoring(route: Route) {
        guard service.isConfigured, let box = BoundingBox(coordinates: route.coordinates)?.expanded(byMeters: 2000) else { return }
        pollTask?.cancel()
        pollTask = Task {
            var failures = 0
            while !Task.isCancelled {
                let ok = await fetch(box)
                failures = ok ? 0 : failures + 1
                // 2 minutes normally; back off to 10 minutes while the service is failing.
                let delay = ok ? 120.0 : min(600, 30 * pow(2, Double(failures)))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// For the browsing map: refetch only when the area changed a lot or data aged.
    func refreshIfNeeded(around center: Coordinate) async {
        guard service.isConfigured, pollTask == nil else { return }
        let box = BoundingBox(coordinates: [center])!.expanded(byMeters: 15_000)
        if let last = lastBrowseFetch, last.area.contains(center), Date().timeIntervalSince(last.at) < 180 { return }
        if await fetch(box) { lastBrowseFetch = (box, Date()) }
    }

    @discardableResult
    private func fetch(_ box: BoundingBox) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await service.incidents(in: box)
            lastError = nil
            return true
        } catch let e as APIError {
            lastError = e
        } catch {
            lastError = .transport(error.localizedDescription)
        }
        return false
    }

    /// Lets a just-submitted report appear without waiting for the next poll.
    func insertLocal(_ report: CommunityReport) {
        guard var s = snapshot else { return }
        s.incidents.removeAll { $0.id == report.id }
        s.incidents.append(Incident(report: report))
        snapshot = s
    }
}

extension Incident {
    init(report r: CommunityReport) {
        let kind: IncidentKind
        switch r.category {
        case .accident: kind = .accident
        case .trafficJam: kind = .congestion
        case .hazard, .objectOnRoad, .stoppedVehicle: kind = .hazard
        case .roadworks: kind = .roadworks
        case .closure: kind = .closure
        case .police: kind = .police
        case .speedCamera: kind = .speedCamera
        case .other: kind = .other
        }
        self.init(id: r.id, kind: kind, severity: .unknown, coordinate: r.coordinate, title: r.category.title,
                  detail: r.note, roadClosed: false, startTime: r.createdAt, endTime: r.expiresAt,
                  updatedAt: r.createdAt, source: .community, report: r)
    }
}

/// Submits and votes on community reports, with a client-side rate limit, region rules
/// and an undo window so a mis-tap never gets sent.
@MainActor
@Observable
final class ReportStore {
    enum SubmitState: Equatable {
        case idle
        case pending(ReportCategory, secondsLeft: Int)
        case sending
        case sent(ReportCategory)
        case failed(String)
    }

    private(set) var state: SubmitState = .idle
    @ObservationIgnored let service: CommunityReportService
    @ObservationIgnored private var limiter = RateLimiter()
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var votedIDs: Set<String> = []
    /// Called after a report reaches the server (used for XP).
    @ObservationIgnored var onSent: (() -> Void)?
    let regionPolicy = ReportRegionPolicy.conservativeDefault

    init(service: CommunityReportService) { self.service = service }

    var isConfigured: Bool { service.isConfigured }

    var allowedCategories: [ReportCategory] {
        regionPolicy.allowedCategories(regionCode: Locale.current.region?.identifier)
    }

    /// Starts a 4-second undo countdown, then sends.
    func submit(_ category: ReportCategory, at fix: LocationFix?, traffic: TrafficStore) {
        guard let fix else { state = .failed("Your location isn't available."); return }
        guard service.isConfigured else { state = .failed("Community reporting isn't set up in this build."); return }
        if case .wait(let s) = limiter.check(at: Date()) {
            state = .failed("You can send another report in \(Int(s.rounded(.up))) seconds.")
            return
        }
        undoTask?.cancel()
        undoTask = Task {
            for left in stride(from: 4, through: 1, by: -1) {
                state = .pending(category, secondsLeft: left)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            state = .sending
            do {
                let r = try await service.submit(NewReport(category: category, coordinate: fix.coordinate,
                                                           heading: fix.hasValidCourse ? fix.course : nil, reportedAt: Date()))
                limiter.record(at: Date())
                traffic.insertLocal(r)
                state = .sent(category)
                onSent?()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func undo() {
        undoTask?.cancel()
        state = .idle
    }

    func reset() { state = .idle }

    func hasVoted(on id: String) -> Bool { votedIDs.contains(id) }

    func vote(_ vote: ReportVote, on report: CommunityReport, traffic: TrafficStore) async -> String? {
        guard !votedIDs.contains(report.id) else { return nil }
        do {
            votedIDs.insert(report.id)
            if let updated = try await service.vote(vote, on: report.id) { traffic.insertLocal(updated) }
            return nil
        } catch {
            votedIDs.remove(report.id)
            return error.localizedDescription
        }
    }
}
