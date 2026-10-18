import Foundation
@testable import OxydeCore

/// Synthetic geometry for tests only. Nothing here is shipped or shown in the app.
enum Fixtures {
    static let origin = Coordinate(latitude: 48.8566, longitude: 2.3522)

    /// Points every `spacing` meters from `start` on `bearing` for `length` meters.
    static func line(from start: Coordinate, bearing: Double, length: Double, spacing: Double = 25) -> [Coordinate] {
        stride(from: 0.0, through: length, by: spacing).map { GeoMath.destination(from: start, bearing: bearing, distance: $0) }
    }

    /// 1 km north, then a right turn and 1 km east.
    static func lRoute(provider: String = "test") -> Route {
        let north = line(from: origin, bearing: 0, length: 1000)
        let corner = north.last!
        let east = line(from: corner, bearing: 90, length: 1000)
        let coords = north + east.dropFirst()
        let cornerIndex = north.count - 1
        let steps = [
            RouteStep(id: 0, instruction: "Head north on Test Street", distance: 1000, startIndex: 0, maneuver: .depart),
            RouteStep(id: 1, instruction: "Turn right onto Example Avenue", distance: 1000, startIndex: cornerIndex, maneuver: .right),
            RouteStep(id: 2, instruction: "Arrive at the destination", distance: 0, startIndex: coords.count - 1, maneuver: .arrive),
        ]
        return Route(name: "Test", coordinates: coords, steps: steps, distance: 2000, expectedTravelTime: 240,
                     calculatedAt: Date(timeIntervalSince1970: 1_000_000), isTrafficAware: true, provider: provider,
                     waypoints: [Waypoint(name: "Start", coordinate: origin),
                                 Waypoint(name: "Destination", coordinate: coords.last!)])
    }

    static func fix(_ c: Coordinate, t: TimeInterval, accuracy: Double = 5, speed: Double = 14, course: Double = -1) -> LocationFix {
        LocationFix(coordinate: c, horizontalAccuracy: accuracy, speed: speed, speedAccuracy: 1, course: course,
                    timestamp: Date(timeIntervalSince1970: 1_000_000 + t))
    }

    /// Drives the route at `speed` m/s with one fix per second.
    static func drive(_ route: Route, speed: Double = 14) -> [LocationFix] {
        let poly = MeasuredPolyline(route.coordinates)
        var fixes: [LocationFix] = []
        var d = 0.0, t = 0.0
        while d <= poly.length + speed {
            let c = poly.coordinate(atDistance: min(d, poly.length))!
            let snap = poly.snap(c)!
            fixes.append(fix(c, t: t, speed: speed, course: snap.segmentBearing))
            d += speed
            t += 1
        }
        return fixes
    }
}
