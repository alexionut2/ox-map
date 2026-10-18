import Foundation

/// Picks a maneuver icon for providers (such as MapKit) whose steps carry an instruction
/// string but no maneuver type. The turn angle is measured from the route geometry
/// around the maneuver point, so the icon always matches the line drawn on the map.
public enum ManeuverClassifier {
    /// Measures bearings over roughly this distance before and after the maneuver, so
    /// tiny polyline wiggles at the junction do not decide the icon.
    static let sampleDistance: Double = 30

    public static func classify(coordinates: [Coordinate], at index: Int, instruction: String,
                                isFirst: Bool, isLast: Bool) -> ManeuverKind {
        if isFirst { return .depart }
        if isLast { return .arrive }
        let text = instruction.lowercased()
        if text.contains("ferry") { return .ferry }
        if text.contains("roundabout") || text.contains("traffic circle") || text.contains("rotary") { return .roundabout }

        guard let angle = turnAngle(coordinates: coordinates, at: index) else {
            return .unknown
        }
        let isExit = text.contains("exit") || text.contains("ramp")
        if text.contains("merge") && abs(angle) < 45 { return .merge }
        if isExit && abs(angle) < 60 { return angle < 0 ? .exitLeft : .exitRight }
        return kind(forAngle: angle)
    }

    /// Positive angles turn right, negative turn left.
    public static func kind(forAngle angle: Double) -> ManeuverKind {
        let a = abs(angle)
        let right = angle > 0
        switch a {
        case ..<20: return .straight
        case ..<50: return right ? .slightRight : .slightLeft
        case ..<135: return right ? .right : .left
        case ..<165: return right ? .sharpRight : .sharpLeft
        default: return .uTurn
        }
    }

    public static func turnAngle(coordinates: [Coordinate], at index: Int) -> Double? {
        guard index > 0, index < coordinates.count - 1 else { return nil }
        let pivot = coordinates[index]
        var before: Coordinate?
        var walked = 0.0
        var i = index
        while i > 0 {
            walked += GeoMath.distance(coordinates[i - 1], coordinates[i])
            before = coordinates[i - 1]
            i -= 1
            if walked >= sampleDistance { break }
        }
        var after: Coordinate?
        walked = 0
        i = index
        while i < coordinates.count - 1 {
            walked += GeoMath.distance(coordinates[i], coordinates[i + 1])
            after = coordinates[i + 1]
            i += 1
            if walked >= sampleDistance { break }
        }
        guard let b = before, let a = after,
              GeoMath.distance(b, pivot) > 1, GeoMath.distance(pivot, a) > 1 else { return nil }
        let inBearing = GeoMath.bearing(from: b, to: pivot)
        let outBearing = GeoMath.bearing(from: pivot, to: a)
        return GeoMath.angleDifference(from: inBearing, to: outBearing)
    }
}
