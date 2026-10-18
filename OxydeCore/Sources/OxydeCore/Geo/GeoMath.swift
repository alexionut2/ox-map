import Foundation

public enum GeoMath {
    public static let earthRadius: Double = 6_371_008.8
    public static let metersPerDegreeLatitude: Double = 111_320

    @inline(__always) static func rad(_ deg: Double) -> Double { deg * .pi / 180 }
    @inline(__always) static func deg(_ rad: Double) -> Double { rad * 180 / .pi }

    /// Great-circle distance in meters (haversine).
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = rad(b.latitude - a.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let lat1 = rad(a.latitude), lat2 = rad(b.latitude)
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b`, in degrees 0..<360.
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = rad(a.latitude), lat2 = rad(b.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalizedDegrees(deg(atan2(y, x)))
    }

    public static func normalizedDegrees(_ d: Double) -> Double {
        let r = d.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Signed smallest difference `to - from` in degrees, in -180...180.
    public static func angleDifference(from: Double, to: Double) -> Double {
        var d = (to - from).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// Destination point given a start, bearing (degrees) and distance (meters).
    public static func destination(from c: Coordinate, bearing: Double, distance: Double) -> Coordinate {
        let δ = distance / earthRadius
        let θ = rad(bearing)
        let φ1 = rad(c.latitude), λ1 = rad(c.longitude)
        let φ2 = asin(sin(φ1) * cos(δ) + cos(φ1) * sin(δ) * cos(θ))
        let λ2 = λ1 + atan2(sin(θ) * sin(δ) * cos(φ1), cos(δ) - sin(φ1) * sin(φ2))
        return Coordinate(latitude: deg(φ2), longitude: normalizedDegrees(deg(λ2) + 180) - 180)
    }

    /// Linear interpolation between two coordinates. Accurate enough for the short
    /// segments of a route polyline.
    public static func interpolate(_ a: Coordinate, _ b: Coordinate, fraction t: Double) -> Coordinate {
        Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                   longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// Projects `p` onto segment `a`-`b` using a local equirectangular approximation.
    /// Returns the fraction along the segment (clamped to 0...1) and the distance in meters.
    public static func project(_ p: Coordinate, ontoSegment a: Coordinate, _ b: Coordinate) -> (fraction: Double, distance: Double) {
        let cosLat = cos(rad((a.latitude + b.latitude) / 2))
        let ax = a.longitude * cosLat, ay = a.latitude
        let bx = b.longitude * cosLat, by = b.latitude
        let px = p.longitude * cosLat, py = p.latitude
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        var t = 0.0
        if len2 > 0 { t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) }
        let snapped = interpolate(a, b, fraction: t)
        return (t, distance(p, snapped))
    }
}
