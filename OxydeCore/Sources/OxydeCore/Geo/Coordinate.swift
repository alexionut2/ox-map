import Foundation

/// A WGS-84 coordinate. OxydeCore uses its own type instead of `CLLocationCoordinate2D`
/// so the core logic has no dependency on CoreLocation and can be tested anywhere.
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90.0...90.0).contains(latitude)
            && (-180.0...180.0).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }

    /// Rounds the coordinate to a number of decimal places. Three decimals is roughly
    /// 110 m of latitude, which is what trip history stores unless the user opts in to
    /// precise locations.
    public func rounded(decimals: Int) -> Coordinate {
        let factor = pow(10.0, Double(decimals))
        return Coordinate(
            latitude: (latitude * factor).rounded() / factor,
            longitude: (longitude * factor).rounded() / factor
        )
    }
}

/// An axis-aligned bounding box in degrees.
public struct BoundingBox: Codable, Hashable, Sendable {
    public var minLatitude: Double
    public var minLongitude: Double
    public var maxLatitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.minLongitude = minLongitude
        self.maxLatitude = maxLatitude
        self.maxLongitude = maxLongitude
    }

    public init?(coordinates: [Coordinate]) {
        guard let first = coordinates.first else { return nil }
        var box = BoundingBox(minLatitude: first.latitude, minLongitude: first.longitude,
                              maxLatitude: first.latitude, maxLongitude: first.longitude)
        for c in coordinates.dropFirst() {
            box.minLatitude = min(box.minLatitude, c.latitude)
            box.minLongitude = min(box.minLongitude, c.longitude)
            box.maxLatitude = max(box.maxLatitude, c.latitude)
            box.maxLongitude = max(box.maxLongitude, c.longitude)
        }
        self = box
    }

    public var center: Coordinate {
        Coordinate(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }

    /// Grows the box by a distance in meters on every side.
    public func expanded(byMeters meters: Double) -> BoundingBox {
        let dLat = meters / GeoMath.metersPerDegreeLatitude
        let midLat = (minLatitude + maxLatitude) / 2
        let metersPerDegLon = max(1, GeoMath.metersPerDegreeLatitude * cos(midLat * .pi / 180))
        let dLon = meters / metersPerDegLon
        return BoundingBox(minLatitude: max(-90, minLatitude - dLat), minLongitude: max(-180, minLongitude - dLon),
                           maxLatitude: min(90, maxLatitude + dLat), maxLongitude: min(180, maxLongitude + dLon))
    }

    public func contains(_ c: Coordinate) -> Bool {
        (minLatitude...maxLatitude).contains(c.latitude) && (minLongitude...maxLongitude).contains(c.longitude)
    }

    /// `minLon,minLat,maxLon,maxLat`, the order used by most traffic APIs.
    public var queryValue: String {
        String(format: "%.5f,%.5f,%.5f,%.5f", minLongitude, minLatitude, maxLongitude, maxLatitude)
    }
}

/// One location fix from the device, already converted from `CLLocation`.
public struct LocationFix: Codable, Hashable, Sendable {
    public var coordinate: Coordinate
    /// Horizontal accuracy radius in meters. Negative means invalid.
    public var horizontalAccuracy: Double
    /// Speed in meters per second. Negative means unknown.
    public var speed: Double
    /// Speed accuracy in m/s. Negative means unknown.
    public var speedAccuracy: Double
    /// Course over ground in degrees from true north. Negative means unknown.
    public var course: Double
    public var timestamp: Date

    public init(coordinate: Coordinate, horizontalAccuracy: Double, speed: Double = -1,
                speedAccuracy: Double = -1, course: Double = -1, timestamp: Date) {
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.course = course
        self.timestamp = timestamp
    }

    public var hasValidSpeed: Bool { speed >= 0 && speedAccuracy >= 0 }
    public var hasValidCourse: Bool { course >= 0 }
}
