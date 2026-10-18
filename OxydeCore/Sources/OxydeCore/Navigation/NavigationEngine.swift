import Foundation

public enum NavigationEvent: Sendable, Equatable {
    case progress(RouteProgress)
    case announce(Announcement)
    case stepAdvanced(Int)
    case offRoute(OffRouteReason)
    case weakSignal
    case signalLost
    case signalRecovered
    case arrivedAtWaypoint(index: Int, waypoint: Waypoint)
    case arrived(Waypoint?)
}

/// Turns a stream of location fixes into route progress, guidance and off-route events.
/// It is a value type with no timers or I/O, so the app drives it and tests can replay
/// recorded drives through it deterministically.
public struct NavigationEngine: Sendable {
    public private(set) var route: Route
    public private(set) var progress: RouteProgress?
    public private(set) var hasArrived = false
    public private(set) var legIndex = 0
    public var scheduler: GuidanceScheduler
    public var offRouteDetector = OffRouteDetector()

    /// How close to a stop counts as having reached it.
    public var arrivalRadius: Double = 30
    /// No fix for this long means the GPS signal is lost.
    public var signalLossInterval: TimeInterval = 10

    private var polyline: MeasuredPolyline
    private var stepStarts: [Double]
    private var lastSegment: Int?
    private var lastStep = 0
    private var lastFixTime: Date?
    private var signalState: SignalState = .good
    private var travelTimeAnchor: (time: TimeInterval, distanceRemaining: Double, at: Date)

    enum SignalState { case good, weak, lost }

    public init(route: Route, scheduler: GuidanceScheduler) {
        self.route = route
        self.scheduler = scheduler
        self.polyline = MeasuredPolyline(route.coordinates)
        self.stepStarts = route.steps.map { _ in 0 }
        self.travelTimeAnchor = (route.expectedTravelTime, route.distance, route.calculatedAt)
        self.stepStarts = Self.computeStepStarts(route: route, polyline: polyline)
    }

    static func computeStepStarts(route: Route, polyline: MeasuredPolyline) -> [Double] {
        route.steps.map { step in
            let idx = min(max(0, step.startIndex), max(0, polyline.cumulative.count - 1))
            return polyline.cumulative.isEmpty ? 0 : polyline.cumulative[idx]
        }
    }

    /// Distance along the route (meters) where a step's maneuver happens.
    public func stepStartDistance(_ index: Int) -> Double? {
        stepStarts.indices.contains(index) ? stepStarts[index] : nil
    }

    public var measuredPolyline: MeasuredPolyline { polyline }

    /// Replaces the route after a reroute. Guidance state is reset so the new first
    /// maneuver is announced.
    public mutating func replaceRoute(_ newRoute: Route, keepLegIndexOffset: Bool = false) {
        route = newRoute
        polyline = MeasuredPolyline(newRoute.coordinates)
        stepStarts = Self.computeStepStarts(route: newRoute, polyline: polyline)
        lastSegment = nil
        lastStep = 0
        if !keepLegIndexOffset { legIndex = 0 }
        progress = nil
        hasArrived = false
        travelTimeAnchor = (newRoute.expectedTravelTime, newRoute.distance, newRoute.calculatedAt)
        scheduler.reset()
        offRouteDetector.reset()
    }

    /// Applies a fresh travel time from the provider for the remainder of the trip
    /// (for example from MapKit's ETA request), so arrival times follow current traffic.
    public mutating func applyTravelTimeRefresh(_ seconds: TimeInterval, at date: Date) {
        guard let p = progress, seconds.isFinite, seconds >= 0 else { return }
        travelTimeAnchor = (seconds, p.distanceRemaining, date)
        progress?.timeRemaining = seconds
        progress?.estimatedArrival = date.addingTimeInterval(seconds)
        progress?.travelTimeUpdatedAt = date
    }

    public mutating func update(with fix: LocationFix) -> [NavigationEvent] {
        guard !hasArrived else { return [] }
        var events: [NavigationEvent] = []
        lastFixTime = fix.timestamp

        guard fix.coordinate.isValid, let snap = polyline.snap(fix.coordinate, hint: lastSegment) else { return [] }

        let verdict = offRouteDetector.evaluate(fix: fix, snap: snap)
        switch verdict {
        case .unusableFix:
            if signalState != .weak { signalState = .weak; events.append(.weakSignal) }
            return events
        case .offRoute(let reason):
            events.append(.offRoute(reason))
            return events
        case .suspect:
            if signalState != .good { signalState = .good; events.append(.signalRecovered) }
            // Keep showing the last on-route progress while the detector decides.
            return events
        case .onRoute:
            if signalState != .good { signalState = .good; events.append(.signalRecovered) }
        }

        // Do not let a noisy fix move progress backwards by more than a few meters.
        var along = snap.distanceAlong
        if let previous = progress?.distanceTraveled, along < previous, previous - along < 25 {
            along = previous
        }
        lastSegment = snap.segmentIndex

        let total = polyline.length
        let remaining = max(0, total - along)

        // Leg handling for multi-stop routes.
        let legEnds = route.legEndDistances.map { $0 * (total / max(route.distance, 1)) }
        while legIndex < legEnds.count - 1, along >= legEnds[legIndex] - arrivalRadius {
            let wp = route.waypoints.indices.contains(legIndex + 1) ? route.waypoints[legIndex + 1] : nil
            legIndex += 1
            if let wp {
                events.append(.arrivedAtWaypoint(index: legIndex - 1, waypoint: wp))
                events.append(.announce(Announcement(text: scheduler.phrasebook.arrivedAtStop(wp.name), stage: .arrival, stepIndex: nil, interrupts: false)))
            }
        }
        let legEnd = legEnds.indices.contains(legIndex) ? legEnds[legIndex] : total
        let remainingInLeg = max(0, legEnd - along)

        // Current step = last step whose maneuver point we have passed.
        var current = 0
        for (i, start) in stepStarts.enumerated() where start <= along + 1 { current = i }
        let upcoming = current + 1 < route.steps.count ? current + 1 : nil
        let following = upcoming.flatMap { $0 + 1 < route.steps.count ? $0 + 1 : nil }

        let timeRemaining: TimeInterval = travelTimeAnchor.distanceRemaining > 0
            ? travelTimeAnchor.time * (remaining / travelTimeAnchor.distanceRemaining)
            : 0

        let p = RouteProgress(
            routeID: route.id,
            snappedCoordinate: snap.coordinate,
            routeBearing: snap.segmentBearing,
            distanceTraveled: along,
            distanceRemaining: remaining,
            distanceRemainingInLeg: remainingInLeg,
            legIndex: legIndex,
            currentStepIndex: current,
            upcomingStepIndex: upcoming,
            distanceToUpcomingManeuver: upcoming.map { max(0, stepStarts[$0] - along) },
            followingStepIndex: following,
            distanceFromUpcomingToFollowing: following.flatMap { f in upcoming.map { stepStarts[f] - stepStarts[$0] } },
            timeRemaining: timeRemaining,
            estimatedArrival: fix.timestamp.addingTimeInterval(timeRemaining),
            travelTimeUpdatedAt: travelTimeAnchor.at,
            offset: snap.offset,
            fixAccuracy: fix.horizontalAccuracy
        )
        progress = p
        if current != lastStep {
            lastStep = current
            events.append(.stepAdvanced(current))
        }
        events.append(.progress(p))

        if let a = scheduler.next(for: p, route: route, speed: max(0, fix.speed)) {
            events.append(.announce(a))
        }

        let destinationDistance = route.destination.map { GeoMath.distance(fix.coordinate, $0.coordinate) } ?? .infinity
        let onLastLeg = legIndex >= route.legEndDistances.count - 1
        if onLastLeg, remaining <= arrivalRadius || destinationDistance <= arrivalRadius {
            hasArrived = true
            events.append(.arrived(route.destination))
        }
        return events
    }

    /// Call about once a second; reports GPS signal loss when fixes stop arriving.
    public mutating func tick(now: Date) -> [NavigationEvent] {
        guard !hasArrived, let last = lastFixTime else { return [] }
        if now.timeIntervalSince(last) > signalLossInterval, signalState != .lost {
            signalState = .lost
            return [.signalLost]
        }
        return []
    }
}
