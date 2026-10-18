import MapKit
import Observation
import OxydeCore

extension PlaceCategory {
    var mapKitCategories: [MKPointOfInterestCategory] {
        switch self {
        case .fuel: return [.gasStation]
        case .evCharging: return [.evCharger]
        case .parking: return [.parking]
        case .restaurant: return [.restaurant]
        case .cafe: return [.cafe, .bakery]
        case .hotel: return [.hotel]
        case .supermarket: return [.foodMarket]
        case .restroom: return [.restroom]
        case .pharmacy: return [.pharmacy]
        case .hospital: return [.hospital]
        case .atm: return [.atm, .bank]
        case .carWash: return []
        case .other: return []
        }
    }

    init?(mapKit: MKPointOfInterestCategory?) {
        guard let mapKit else { return nil }
        switch mapKit {
        case .gasStation: self = .fuel
        case .evCharger: self = .evCharging
        case .parking: self = .parking
        case .restaurant: self = .restaurant
        case .cafe, .bakery: self = .cafe
        case .hotel: self = .hotel
        case .foodMarket: self = .supermarket
        case .restroom: self = .restroom
        case .pharmacy: self = .pharmacy
        case .hospital: self = .hospital
        case .atm, .bank: self = .atm
        default: self = .other
        }
    }

    /// Words for natural-language search when MapKit has no category (car washes).
    var searchPhrase: String { self == .carWash ? "car wash" : title }
}

extension SearchRegion {
    var mkRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: center.cl, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
    }
}

/// Place search through MapKit. Results are whatever Apple returns: no padding with
/// placeholder entries, no invented ratings or hours.
final class MapKitSearchService: PlaceSearchService, @unchecked Sendable {
    private let geocoder = CLGeocoder()
    private let geocodeCache = NSCache<NSString, PlaceBox>()
    final class PlaceBox { let place: Place; init(_ p: Place) { place = p } }

    static func place(from item: MKMapItem) -> Place {
        let coordinate = Coordinate(item.placemark.coordinate)
        let name = item.name ?? item.placemark.name ?? "Dropped pin"
        return Place(id: Place.syntheticID(name: name, coordinate: coordinate), name: name, coordinate: coordinate,
                     address: address(of: item.placemark),
                     category: PlaceCategory(mapKit: item.pointOfInterestCategory), phone: item.phoneNumber,
                     website: item.url, timeZoneIdentifier: item.timeZone?.identifier, provider: "Apple Maps")
    }

    static func address(of p: CLPlacemark) -> String? {
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, p.locality, p.administrativeArea, p.country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    func search(text: String, near region: SearchRegion?) async throws -> [Place] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let c = CoordinateParser.parse(trimmed) {
            // A typed coordinate is a destination in itself.
            let nearby = try? await reverseGeocode(c)
            return [Place(id: Place.syntheticID(name: trimmed, coordinate: c),
                          name: String(format: "%.5f, %.5f", c.latitude, c.longitude),
                          coordinate: c, address: nearby?.address ?? nearby?.name, provider: "Coordinates")]
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        if let region { request.region = region.mkRegion }
        return try await run(request)
    }

    func search(completion: MKLocalSearchCompletion, near region: SearchRegion?) async throws -> [Place] {
        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = [.address, .pointOfInterest]
        if let region { request.region = region.mkRegion }
        return try await run(request)
    }

    func search(category: PlaceCategory, near region: SearchRegion) async throws -> [Place] {
        let cats = category.mapKitCategories
        if cats.isEmpty {
            let r = MKLocalSearch.Request()
            r.naturalLanguageQuery = category.searchPhrase
            r.region = region.mkRegion
            r.resultTypes = .pointOfInterest
            return try await run(r)
        }
        let request = MKLocalPointsOfInterestRequest(center: region.center.cl, radius: min(region.radius, 50_000))
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: cats)
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.map(Self.place(from:))
        } catch {
            throw Self.map(error)
        }
    }

    /// Searches at points ahead on the route and ranks the results by distance along it.
    func searchAlongRoute(category: PlaceCategory, route: Route, traveled: Double) async throws -> [AlongRouteRanker.Candidate] {
        let poly = MeasuredPolyline(route.coordinates)
        let remaining = poly.length - traveled
        let spacing = max(3000, min(15_000, remaining / 6))
        let samples = poly.samples(every: spacing, from: traveled + 1000, limit: 6)
        var found: [Place] = []
        try await withThrowingTaskGroup(of: [Place].self) { group in
            for s in samples {
                group.addTask {
                    (try? await self.search(category: category, near: SearchRegion(center: s.coordinate, radius: spacing * 0.6))) ?? []
                }
            }
            for try await batch in group { found.append(contentsOf: batch) }
        }
        return AlongRouteRanker.rank(found, polyline: poly, traveled: traveled)
    }

    func reverseGeocode(_ coordinate: Coordinate) async throws -> Place {
        // Apple rate-limits geocoding; cache by ~10 m cell so repeated taps don't refetch.
        let key = "\(coordinate.rounded(decimals: 4).latitude),\(coordinate.rounded(decimals: 4).longitude)" as NSString
        if let hit = geocodeCache.object(forKey: key) { return hit.place }
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        } catch {
            throw Self.map(error)
        }
        let p = placemarks.first
        let name = p?.name ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        let place = Place(id: Place.syntheticID(name: name, coordinate: coordinate), name: name, coordinate: coordinate,
                          address: p.flatMap(Self.address(of:)), provider: "Apple Maps")
        geocodeCache.setObject(PlaceBox(place), forKey: key)
        return place
    }

    private func run(_ request: MKLocalSearch.Request) async throws -> [Place] {
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.map(Self.place(from:))
        } catch {
            throw Self.map(error)
        }
    }

    static func map(_ error: Error) -> Error {
        if let e = error as? MKError {
            switch e.code {
            case .placemarkNotFound: return SearchError.noResults
            case .loadingThrottled: return APIError.rateLimited(retryAfter: 30)
            default: break
            }
        }
        if let e = error as? CLError, e.code == .network { return APIError.offline }
        if (error as NSError).domain == NSURLErrorDomain { return APIError.offline }
        return error
    }
}

enum SearchError: LocalizedError {
    case noResults
    var errorDescription: String? { "No results." }
}

/// Live autocomplete with MKLocalSearchCompleter, debounced by MapKit itself.
@MainActor
@Observable
final class SearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var error: String?
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    func update(query: String, region: SearchRegion?) {
        if let region { completer.region = region.mkRegion }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = q
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = completer.results
        Task { @MainActor in
            self.results = r
            self.error = nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let message = (error as? MKError)?.code == .placemarkNotFound ? nil : error.localizedDescription
        Task { @MainActor in self.error = message }
    }
}
