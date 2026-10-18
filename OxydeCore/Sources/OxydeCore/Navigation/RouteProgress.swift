import Foundation

/// A snapshot of where the vehicle is along the active route.
public struct RouteProgress: Sendable, Equatable {
    public var routeID: UUID
    public var snappedCoordinate: Coordinate
    /// Bearing of the route at the vehicle's position, used to orient the camera.
    public var routeBearing: Double
    public var distanceTraveled: Double
    public var distanceRemaining: Double
    /// Distance to the next stop or, on the last leg, to the destination.
    public var distanceRemainingInLeg: Double
    public var legIndex: Int
    /// The step currently being driven.
    public var currentStepIndex: Int
    /// The next maneuver the driver has to make.
    public var upcomingStepIndex: Int?
    public var distanceToUpcomingManeuver: Double?
    /// The maneuver after the upcoming one, shown as "Then…" when it follows closely.
    public var followingStepIndex: Int?
    public var distanceFromUpcomingToFollowing: Double?
    /// Remaining travel time, derived from the provider's travel time (refreshed while
    /// driving when the provider supports it) and the share of the route still ahead.
    public var timeRemaining: TimeInterval
    public var estimatedArrival: Date
    /// When the provider travel time behind `timeRemaining` was last fetched.
    public var travelTimeUpdatedAt: Date
    /// Distance between the raw fix and the route line.
    public var offset: Double
    public var fixAccuracy: Double
}

/// Decides when the vehicle has left the planned route. A single noisy fix never
/// triggers a reroute: it takes several consecutive fixes that are clearly off the line,
/// or clearly driving the wrong way, and fixes too inaccurate to judge are ignored.
public struct OffRouteDetector: Sendable {
    public var minimumThreshold: Double = 40
    public var maximumThreshold: Double = 90
    /// Fixes worse than this are too poor to make a routing decision.
    public var maximumUsableAccuracy: Double = 65
    public var requiredConsecutiveFixes: Int = 3
    public var requiredDuration: TimeInterval = 4

    private var offSince: Date?
    private var offCount = 0
    private var wrongWayCount = 0

    public init() {}

    public enum Verdict: Equatable, Sendable { case onRoute, suspect, offRoute(OffRouteReason), unusableFix }

    public func threshold(forAccuracy accuracy: Double) -> Double {
        min(maximumThreshold, max(minimumThreshold, accuracy * 1.5))
    }

    public mutating func evaluate(fix: LocationFix, snap: MeasuredPolyline.Snap) -> Verdict {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maximumUsableAccuracy else {
            return .unusableFix
        }
        // Driving the opposite way along the route at speed.
        if fix.hasValidCourse, fix.speed > 5 {
            let diff = abs(GeoMath.angleDifference(from: snap.segmentBearing, to: fix.course))
            wrongWayCount = diff > 150 ? wrongWayCount + 1 : 0
            if wrongWayCount >= 4 {
                reset()
                return .offRoute(.wrongDirection)
            }
        }
        if snap.offset > threshold(forAccuracy: fix.horizontalAccuracy) {
            offCount += 1
            if offSince == nil { offSince = fix.timestamp }
            if offCount >= requiredConsecutiveFixes,
               let since = offSince, fix.timestamp.timeIntervalSince(since) >= requiredDuration {
                reset()
                return .offRoute(.leftRoute)
            }
            return .suspect
        }
        offCount = 0
        offSince = nil
        return .onRoute
    }

    public mutating func reset() {
        offCount = 0
        offSince = nil
        wrongWayCount = 0
    }
}

public enum OffRouteReason: String, Sendable, Equatable { case leftRoute, wrongDirection }
