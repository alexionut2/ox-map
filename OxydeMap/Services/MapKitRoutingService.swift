import MapKit
import OxydeCore

extension MKPolyline {
    var coordinates: [Coordinate] {
        var buffer = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&buffer, range: NSRange(location: 0, length: pointCount))
        return buffer.map(Coordinate.init)
    }
}

extension Waypoint {
    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.cl))
        item.name = name
        return item
    }
}

/// Routing through Apple's MKDirections. Travel times are Apple's, which account for
/// traffic for driving routes; nothing here estimates or invents a route.
struct MapKitRoutingService: RoutingService {
    var capabilities: RoutingCapabilities {
        RoutingCapabilities(providerName: "Apple Maps", supportsAlternatives: true, supportsAvoidTolls: true,
                            supportsAvoidHighways: true, supportsAvoidFerries: false, supportsMultipleStops: true,
                            supportsTravelTimeRefresh: true, providesLaneGuidance: false, providesSpeedLimits: false,
                            trafficAwareTravelTimes: true)
    }

    func routes(for request: RouteRequest) async throws -> [Route] {
        let points = [request.origin] + request.stops
        guard points.count >= 2 else { return [] }
        let multiLeg = points.count > 2

        // Each leg is its own MKDirections request; alternatives only make sense for a
        // single leg, so multi-stop trips use the provider's best route per leg.
        var legs: [[Route]] = []
        for i in 0..<(points.count - 1) {
            try Task.checkCancellation()
            let leg = try await calculate(from: points[i], to: points[i + 1], preferences: request.preferences,
                                          alternatives: !multiLeg && request.preferences.requestAlternatives,
                                          departure: request.departureDate)
            guard !leg.isEmpty else { throw RoutingError.noRoute }
            legs.append(leg)
        }
        if multiLeg {
            let best = legs.compactMap(\.first)
            return Route.combining(legs: best, waypoints: points).map { [$0] } ?? []
        }
        return legs[0].map { var r = $0; r.waypoints = points; return r }
    }

    func travelTime(from origin: Coordinate, to destination: Coordinate, preferences: RoutePreferences) async throws -> TimeInterval {
        let r = makeRequest(from: Waypoint(name: "", coordinate: origin), to: Waypoint(name: "", coordinate: destination),
                            preferences: preferences, alternatives: false, departure: Date())
        do {
            return try await MKDirections(request: r).calculateETA().expectedTravelTime
        } catch {
            throw Self.map(error)
        }
    }

    private func makeRequest(from: Waypoint, to: Waypoint, preferences: RoutePreferences, alternatives: Bool, departure: Date) -> MKDirections.Request {
        let r = MKDirections.Request()
        r.source = from.mapItem
        r.destination = to.mapItem
        r.transportType = .automobile
        r.requestsAlternateRoutes = alternatives
        r.departureDate = departure
        r.tollPreference = preferences.avoidTolls ? .avoid : .any
        r.highwayPreference = preferences.avoidHighways ? .avoid : .any
        return r
    }

    private func calculate(from: Waypoint, to: Waypoint, preferences: RoutePreferences, alternatives: Bool, departure: Date) async throws -> [Route] {
        let request = makeRequest(from: from, to: to, preferences: preferences, alternatives: alternatives, departure: departure)
        let response: MKDirections.Response
        do {
            response = try await MKDirections(request: request).calculate()
        } catch {
            throw Self.map(error)
        }
        let now = Date()
        return response.routes.map { Self.convert($0, calculatedAt: now) }
    }

    static func convert(_ mk: MKRoute, calculatedAt: Date) -> Route {
        var coords: [Coordinate] = []
        var steps: [RouteStep] = []
        for (i, step) in mk.steps.enumerated() {
            let stepCoords = step.polyline.coordinates
            let start = coords.isEmpty ? 0 : coords.count - 1
            if coords.isEmpty { coords = stepCoords } else { coords.append(contentsOf: stepCoords.dropFirst()) }
            steps.append(RouteStep(id: i, instruction: step.instructions, distance: step.distance, startIndex: start,
                                   maneuver: .unknown, notice: step.notice))
        }
        if coords.count < 2 { coords = mk.polyline.coordinates }
        // MapKit steps have no maneuver type: classify the icon from the geometry.
        for i in steps.indices {
            steps[i].maneuver = ManeuverClassifier.classify(coordinates: coords, at: steps[i].startIndex,
                                                            instruction: steps[i].instruction,
                                                            isFirst: i == 0, isLast: i == steps.count - 1)
        }
        // MapKit's first step is often an empty "start" step of zero length.
        if let first = steps.first, first.instruction.isEmpty, first.distance < 1, steps.count > 1 {
            steps.removeFirst()
            for i in steps.indices { steps[i].id = i }
            steps[0].maneuver = .depart
        }
        return Route(name: mk.name, coordinates: coords, steps: steps, distance: mk.distance,
                     expectedTravelTime: mk.expectedTravelTime, calculatedAt: calculatedAt,
                     advisoryNotices: mk.advisoryNotices, hasTolls: mk.hasTolls, hasHighways: mk.hasHighways,
                     isTrafficAware: true, provider: "Apple Maps")
    }

    static func map(_ error: Error) -> Error {
        if let e = error as? MKError {
            switch e.code {
            case .loadingThrottled: return APIError.rateLimited(retryAfter: 60)
            case .serverFailure: return APIError.server(status: 503)
            case .directionsNotFound, .placemarkNotFound: return RoutingError.noRoute
            default: break
            }
        }
        if (error as NSError).domain == NSURLErrorDomain { return APIError.offline }
        return error
    }
}

enum RoutingError: LocalizedError {
    case noRoute
    case noLocation
    var errorDescription: String? {
        switch self {
        case .noRoute: return "No driving route was found between these places."
        case .noLocation: return "Your current location isn't available yet."
        }
    }
}
