import Foundation

/// A finished trip summary. Average speed is computed from the recorded fixes; no top
/// speed is kept and nothing is framed as a performance score.
public struct TripSummary: Codable, Hashable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    public var distance: Double
    public var duration: TimeInterval
    public var movingDuration: TimeInterval
    public var averageMovingSpeed: Double?
    public var start: Coordinate?
    public var end: Coordinate?
    /// Encoded polyline of a simplified route shape, only with precise trip history.
    public var encodedShape: String?
    public var destinationName: String?
}

/// Accumulates fixes during navigation when the user has opted into trip history.
public struct TripRecorder: Sendable {
    public let precision: TripPrecision
    public let startedAt: Date
    public var destinationName: String?
    private var lastAccepted: LocationFix?
    private var points: [Coordinate] = []
    private(set) var distance = 0.0
    private(set) var movingDuration: TimeInterval = 0
    private var first: Coordinate?

    /// Fixes worse than this are not used for distance.
    static let maxAccuracy = 50.0
    /// Movement below this between accepted fixes is GPS jitter.
    static let minMovement = 5.0

    public init(precision: TripPrecision, startedAt: Date, destinationName: String?) {
        self.precision = precision
        self.startedAt = startedAt
        self.destinationName = destinationName
    }

    public mutating func add(_ fix: LocationFix) {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= Self.maxAccuracy, fix.coordinate.isValid else { return }
        if first == nil { first = fix.coordinate }
        guard let last = lastAccepted else {
            lastAccepted = fix
            points.append(fix.coordinate)
            return
        }
        let d = GeoMath.distance(last.coordinate, fix.coordinate)
        guard d >= Self.minMovement else { return }
        let dt = fix.timestamp.timeIntervalSince(last.timestamp)
        // Reject jumps faster than ~250 km/h: they are GPS errors, not driving.
        if dt > 0, d / dt > 70 { return }
        distance += d
        if dt > 0, dt < 30 { movingDuration += dt }
        lastAccepted = fix
        points.append(fix.coordinate)
    }

    public func finish(at end: Date) -> TripSummary {
        let precise = precision == .precise
        let lastPoint = lastAccepted?.coordinate
        return TripSummary(
            startedAt: startedAt, endedAt: end, distance: distance,
            duration: end.timeIntervalSince(startedAt), movingDuration: movingDuration,
            averageMovingSpeed: movingDuration > 60 ? distance / movingDuration : nil,
            start: precise ? first : first?.rounded(decimals: 3),
            end: precise ? lastPoint : lastPoint?.rounded(decimals: 3),
            encodedShape: precise ? PolylineCodec.encode(PolylineSimplifier.simplify(points, tolerance: 15)) : nil,
            destinationName: destinationName)
    }
}
