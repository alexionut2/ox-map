import Foundation

/// A polyline with precomputed cumulative distances, used for snapping location fixes
/// to a route and measuring progress along it.
public struct MeasuredPolyline: Sendable {
    public let coordinates: [Coordinate]
    /// `cumulative[i]` is the distance in meters from the first point to point `i`.
    public let cumulative: [Double]

    public init(_ coordinates: [Coordinate]) {
        self.coordinates = coordinates
        var acc: [Double] = []
        acc.reserveCapacity(coordinates.count)
        var total = 0.0
        for (i, c) in coordinates.enumerated() {
            if i > 0 { total += GeoMath.distance(coordinates[i - 1], c) }
            acc.append(total)
        }
        self.cumulative = acc
    }

    public var length: Double { cumulative.last ?? 0 }

    public struct Snap: Sendable, Equatable {
        public var segmentIndex: Int
        public var coordinate: Coordinate
        public var distanceAlong: Double
        public var offset: Double
        public var segmentBearing: Double
    }

    /// Snaps a point to the polyline. When `hint` is given, segments near the previous
    /// position are searched first so a route that doubles back on itself does not make
    /// the vehicle jump to the wrong side; the whole line is searched if nothing nearby
    /// is close.
    public func snap(_ p: Coordinate, hint: Int? = nil, window: Int = 60) -> Snap? {
        guard coordinates.count >= 2 else { return nil }
        let lastSegment = coordinates.count - 2
        func best(in range: ClosedRange<Int>) -> Snap? {
            var result: Snap?
            for i in range {
                let a = coordinates[i], b = coordinates[i + 1]
                let proj = GeoMath.project(p, ontoSegment: a, b)
                if result == nil || proj.distance < result!.offset {
                    let segLen = cumulative[i + 1] - cumulative[i]
                    result = Snap(segmentIndex: i,
                                  coordinate: GeoMath.interpolate(a, b, fraction: proj.fraction),
                                  distanceAlong: cumulative[i] + segLen * proj.fraction,
                                  offset: proj.distance,
                                  segmentBearing: GeoMath.bearing(from: a, to: b))
                }
            }
            return result
        }
        if let hint {
            let lo = max(0, min(lastSegment, hint) - 2)
            let hi = min(lastSegment, hint + window)
            if let local = best(in: lo...hi), local.offset < 50 { return local }
        }
        return best(in: 0...lastSegment)
    }

    /// The coordinate at a given distance along the line.
    public func coordinate(atDistance d: Double) -> Coordinate? {
        guard let first = coordinates.first else { return nil }
        if d <= 0 { return first }
        if d >= length { return coordinates.last }
        var lo = 0, hi = cumulative.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= d { lo = mid } else { hi = mid }
        }
        let segLen = cumulative[hi] - cumulative[lo]
        let t = segLen > 0 ? (d - cumulative[lo]) / segLen : 0
        return GeoMath.interpolate(coordinates[lo], coordinates[hi], fraction: t)
    }

    /// Splits the line at a distance, returning the traveled and remaining parts. Used to
    /// draw the part already driven in a muted color.
    public func split(atDistance d: Double) -> (traveled: [Coordinate], remaining: [Coordinate]) {
        guard coordinates.count >= 2, let point = coordinate(atDistance: d) else { return ([], coordinates) }
        let idx = cumulative.lastIndex(where: { $0 <= d }) ?? 0
        let traveled = Array(coordinates[0...idx]) + [point]
        let remaining = [point] + Array(coordinates[(idx + 1)...])
        return (traveled, remaining)
    }

    /// Evenly spaced sample points from `start` to the end of the line. Used for search
    /// along the route.
    public func samples(every spacing: Double, from start: Double = 0, limit: Int = 20) -> [(distance: Double, coordinate: Coordinate)] {
        guard spacing > 0, length > 0 else { return [] }
        var out: [(Double, Coordinate)] = []
        var d = max(0, start)
        while d <= length && out.count < limit {
            if let c = coordinate(atDistance: d) { out.append((d, c)) }
            d += spacing
        }
        return out
    }
}

public enum PolylineSimplifier {
    /// Douglas–Peucker simplification with a tolerance in meters. Trip history uses it so
    /// stored route shapes keep their outline without a fix every second.
    public static func simplify(_ points: [Coordinate], tolerance: Double) -> [Coordinate] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (s, e) = stack.popLast() {
            guard e > s + 1 else { continue }
            var maxDist = 0.0, index = s
            for i in (s + 1)..<e {
                let d = GeoMath.project(points[i], ontoSegment: points[s], points[e]).distance
                if d > maxDist { maxDist = d; index = i }
            }
            if maxDist > tolerance {
                keep[index] = true
                stack.append((s, index))
                stack.append((index, e))
            }
        }
        return points.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }
}

/// Google encoded-polyline format (precision 5), used to store simplified trip shapes
/// and to put routes into share links compactly.
public enum PolylineCodec {
    public static func encode(_ coordinates: [Coordinate], precision: Double = 1e5) -> String {
        var result = ""
        var prevLat = 0, prevLon = 0
        func append(_ value: Int) {
            var v = value < 0 ? ~(value << 1) : (value << 1)
            while v >= 0x20 {
                result.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (v & 0x1f)) + 63)))
                v >>= 5
            }
            result.unicodeScalars.append(UnicodeScalar(UInt8(v + 63)))
        }
        for c in coordinates {
            let lat = Int((c.latitude * precision).rounded())
            let lon = Int((c.longitude * precision).rounded())
            append(lat - prevLat)
            append(lon - prevLon)
            prevLat = lat
            prevLon = lon
        }
        return result
    }

    public static func decode(_ string: String, precision: Double = 1e5) -> [Coordinate]? {
        let bytes = Array(string.utf8)
        var index = 0, lat = 0, lon = 0
        var out: [Coordinate] = []
        func next() -> Int? {
            var result = 0, shift = 0
            while true {
                guard index < bytes.count else { return nil }
                let b = Int(bytes[index]) - 63
                index += 1
                guard b >= 0 else { return nil }
                result |= (b & 0x1f) << shift
                shift += 5
                if b < 0x20 { break }
                if shift > 60 { return nil }
            }
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }
        while index < bytes.count {
            guard let dLat = next(), let dLon = next() else { return nil }
            lat += dLat
            lon += dLon
            out.append(Coordinate(latitude: Double(lat) / precision, longitude: Double(lon) / precision))
        }
        return out
    }
}
