import Foundation

public enum PlaceCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case fuel, evCharging, parking, restaurant, cafe, hotel, supermarket, restroom, pharmacy, hospital, atm, carWash, other
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fuel: return "Fuel"
        case .evCharging: return "EV Charging"
        case .parking: return "Parking"
        case .restaurant: return "Food"
        case .cafe: return "Coffee"
        case .hotel: return "Hotels"
        case .supermarket: return "Groceries"
        case .restroom: return "Restrooms"
        case .pharmacy: return "Pharmacy"
        case .hospital: return "Hospital"
        case .atm: return "ATM"
        case .carWash: return "Car Wash"
        case .other: return "Place"
        }
    }

    public var symbol: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .evCharging: return "bolt.car.fill"
        case .parking: return "parkingsign.circle.fill"
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .hotel: return "bed.double.fill"
        case .supermarket: return "cart.fill"
        case .restroom: return "toilet.fill"
        case .pharmacy: return "cross.case.fill"
        case .hospital: return "cross.fill"
        case .atm: return "banknote.fill"
        case .carWash: return "car.side.and.exclamationmark"
        case .other: return "mappin"
        }
    }

    /// Categories shown as large quick-search buttons.
    public static let quickSearch: [PlaceCategory] = [.fuel, .evCharging, .parking, .restaurant, .cafe, .hotel, .supermarket, .restroom]
    /// Categories offered for search along the route.
    public static let alongRoute: [PlaceCategory] = [.fuel, .evCharging, .restaurant, .cafe, .restroom, .parking]
}

/// EV charger attributes. Only filled when the data provider supplies them; Apple Maps
/// does not, so connector filters are disabled with an explanation in that case.
public struct ChargerInfo: Codable, Hashable, Sendable {
    public enum Connector: String, Codable, Sendable, CaseIterable { case ccs1, ccs2, chademo, nacs, type2, j1772 }
    public var connectors: [Connector]
    public var maxPowerKW: Double?
    public var availablePorts: Int?
}

public struct Place: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var coordinate: Coordinate
    public var address: String?
    public var category: PlaceCategory?
    public var phone: String?
    public var website: URL?
    /// Only from providers that supply ratings; never estimated.
    public var rating: Double?
    public var openingHours: [String]?
    public var charger: ChargerInfo?
    public var timeZoneIdentifier: String?
    public var provider: String

    public init(id: String, name: String, coordinate: Coordinate, address: String? = nil, category: PlaceCategory? = nil,
                phone: String? = nil, website: URL? = nil, rating: Double? = nil, openingHours: [String]? = nil,
                charger: ChargerInfo? = nil, timeZoneIdentifier: String? = nil, provider: String) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.address = address
        self.category = category
        self.phone = phone
        self.website = website
        self.rating = rating
        self.openingHours = openingHours
        self.charger = charger
        self.timeZoneIdentifier = timeZoneIdentifier
        self.provider = provider
    }

    public var waypoint: Waypoint { Waypoint(name: name, coordinate: coordinate, address: address) }

    /// A stable ID for places without a provider ID, from name and rounded position.
    public static func syntheticID(name: String, coordinate: Coordinate) -> String {
        let c = coordinate.rounded(decimals: 5)
        return "\(name.lowercased())@\(c.latitude),\(c.longitude)"
    }
}

public enum CoordinateParser {
    /// Parses "37.3349, -122.0090", "37.3349 -122.0090", "geo:37.33,-122.00" and
    /// degrees with hemispheres such as "37.3349 N, 122.0090 W".
    public static func parse(_ input: String) -> Coordinate? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("GEO:") { s.removeFirst(4) }
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        s = s.replacingOccurrences(of: "°", with: " ")
        let separators = CharacterSet(charactersIn: ", ;")
        let parts = s.components(separatedBy: separators).filter { !$0.isEmpty }

        var numbers: [Double] = []
        var hemis: [Character?] = []
        var i = 0
        while i < parts.count {
            var token = parts[i]
            var hemi: Character?
            if let last = token.last, "NSEW".contains(last) { hemi = last; token.removeLast() }
            if token.isEmpty, i > 0, hemi != nil, !hemis.isEmpty, hemis[hemis.count - 1] == nil {
                hemis[hemis.count - 1] = hemi
                i += 1
                continue
            }
            guard let v = Double(token) else { return nil }
            numbers.append(v)
            hemis.append(hemi)
            i += 1
        }
        guard numbers.count == 2 else { return nil }
        var lat = numbers[0], lon = numbers[1]
        if let h = hemis[0], h == "E" || h == "W", let h2 = hemis[1], h2 == "N" || h2 == "S" {
            swap(&lat, &lon)
            hemis.swapAt(0, 1)
        }
        if hemis[0] == "S" { lat = -abs(lat) }
        if hemis[1] == "W" { lon = -abs(lon) }
        let c = Coordinate(latitude: lat, longitude: lon)
        guard (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon) else { return nil }
        return c
    }
}

/// Ranks places found near a route by how far ahead they are and how far off the line.
public enum AlongRouteRanker {
    public struct Candidate: Sendable, Equatable {
        public var place: Place
        public var distanceAhead: Double
        public var detourOffset: Double
    }

    public static func rank(_ places: [Place], polyline: MeasuredPolyline, traveled: Double,
                            maxOffset: Double = 1500, limit: Int = 25) -> [Candidate] {
        var seen = Set<String>()
        return places.compactMap { p -> Candidate? in
            guard seen.insert(p.id).inserted, let snap = polyline.snap(p.coordinate),
                  snap.offset <= maxOffset, snap.distanceAlong >= traveled else { return nil }
            return Candidate(place: p, distanceAhead: snap.distanceAlong - traveled, detourOffset: snap.offset)
        }
        // A place 1 km off the route costs about as much as one 4 km further along it.
        .sorted { ($0.distanceAhead + $0.detourOffset * 4) < ($1.distanceAhead + $1.detourOffset * 4) }
        .prefix(limit)
        .map { $0 }
    }
}
