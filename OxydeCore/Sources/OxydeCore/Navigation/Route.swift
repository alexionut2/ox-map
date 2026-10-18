import Foundation

/// The direction a maneuver turns. Derived from route geometry when the provider does
/// not say, and used only to pick an icon: spoken and written instructions always come
/// from the provider's own text.
public enum ManeuverKind: String, Codable, Sendable, CaseIterable {
    case depart
    case straight
    case slightLeft, slightRight
    case left, right
    case sharpLeft, sharpRight
    case uTurn
    case roundabout
    case exitLeft, exitRight
    case merge
    case ferry
    case arrive
    case waypoint
    case unknown

    /// SF Symbol name for the phone UI and CarPlay maneuver images.
    public var symbolName: String {
        switch self {
        case .depart: return "location.north.line.fill"
        case .straight: return "arrow.up"
        case .slightLeft: return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .sharpLeft: return "arrow.turn.left.down"
        case .sharpRight: return "arrow.turn.right.down"
        case .uTurn: return "arrow.uturn.down"
        case .roundabout: return "arrow.triangle.turn.up.right.circle"
        case .exitLeft: return "arrow.up.left"
        case .exitRight: return "arrow.up.right"
        case .merge: return "arrow.merge"
        case .ferry: return "ferry.fill"
        case .arrive: return "mappin.circle.fill"
        case .waypoint: return "flag.checkered"
        case .unknown: return "arrow.up"
        }
    }
}

/// One lane at a junction, only ever filled from provider-supplied lane data.
public struct LaneInfo: Codable, Hashable, Sendable {
    public enum Direction: String, Codable, Sendable { case straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn }
    public var directions: [Direction]
    public var isRecommended: Bool
    public init(directions: [Direction], isRecommended: Bool) {
        self.directions = directions
        self.isRecommended = isRecommended
    }
}

public struct RouteStep: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    /// Provider's instruction for the maneuver at the start of this step, e.g.
    /// "Turn right onto Market St". Empty when the provider gave none.
    public var instruction: String
    /// Length of the step in meters, from this maneuver to the next.
    public var distance: Double
    /// Index into `Route.coordinates` where the maneuver happens.
    public var startIndex: Int
    public var maneuver: ManeuverKind
    public var notice: String?
    /// Lane guidance. `nil` means the provider did not supply lane data; never synthesized.
    public var lanes: [LaneInfo]?
    /// Leg this step belongs to, for multi-stop routes.
    public var legIndex: Int

    public init(id: Int, instruction: String, distance: Double, startIndex: Int,
                maneuver: ManeuverKind, notice: String? = nil, lanes: [LaneInfo]? = nil, legIndex: Int = 0) {
        self.id = id
        self.instruction = instruction
        self.distance = distance
        self.startIndex = startIndex
        self.maneuver = maneuver
        self.notice = notice
        self.lanes = lanes
        self.legIndex = legIndex
    }
}

/// A place the route passes through or ends at.
public struct Waypoint: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var coordinate: Coordinate
    public var address: String?

    public init(id: UUID = UUID(), name: String, coordinate: Coordinate, address: String? = nil) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.address = address
    }
}

/// A driving route as returned by a routing provider and normalized for Oxyde Map.
public struct Route: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Provider's route label, e.g. "I-280 S".
    public var name: String
    public var coordinates: [Coordinate]
    public var steps: [RouteStep]
    /// Total length in meters, as reported by the provider.
    public var distance: Double
    /// Provider's expected travel time in seconds when the route was calculated.
    public var expectedTravelTime: TimeInterval
    public var calculatedAt: Date
    public var advisoryNotices: [String]
    public var hasTolls: Bool
    public var hasHighways: Bool
    /// Whether the provider says its travel time accounts for live or typical traffic.
    public var isTrafficAware: Bool
    public var provider: String
    /// Distance along the route, in meters, where each intermediate stop and the final
    /// destination are reached.
    public var legEndDistances: [Double]
    public var waypoints: [Waypoint]

    public init(id: UUID = UUID(), name: String, coordinates: [Coordinate], steps: [RouteStep],
                distance: Double, expectedTravelTime: TimeInterval, calculatedAt: Date = Date(),
                advisoryNotices: [String] = [], hasTolls: Bool = false, hasHighways: Bool = false,
                isTrafficAware: Bool, provider: String, legEndDistances: [Double]? = nil, waypoints: [Waypoint] = []) {
        self.id = id
        self.name = name
        self.coordinates = coordinates
        self.steps = steps
        self.distance = distance
        self.expectedTravelTime = expectedTravelTime
        self.calculatedAt = calculatedAt
        self.advisoryNotices = advisoryNotices
        self.hasTolls = hasTolls
        self.hasHighways = hasHighways
        self.isTrafficAware = isTrafficAware
        self.provider = provider
        self.legEndDistances = legEndDistances ?? [distance]
        self.waypoints = waypoints
    }

    public var destination: Waypoint? { waypoints.last }

    /// Joins consecutive legs (each calculated A→B by the provider) into one route.
    public static func combining(legs: [Route], waypoints: [Waypoint]) -> Route? {
        guard let first = legs.first else { return nil }
        if legs.count == 1 {
            var r = first
            r.waypoints = waypoints
            r.legEndDistances = [first.distance]
            return r
        }
        var coords: [Coordinate] = []
        var steps: [RouteStep] = []
        var legEnds: [Double] = []
        var total = 0.0, time = 0.0
        var notices: [String] = []
        for (legIndex, leg) in legs.enumerated() {
            let offset = coords.isEmpty ? 0 : coords.count - 1
            let legCoords = coords.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst())
            coords.append(contentsOf: legCoords)
            for step in leg.steps {
                var s = step
                s.id = steps.count
                s.startIndex = step.startIndex + offset
                s.legIndex = legIndex
                if legIndex < legs.count - 1, step.maneuver == .arrive { s.maneuver = .waypoint }
                steps.append(s)
            }
            total += leg.distance
            time += leg.expectedTravelTime
            legEnds.append(total)
            notices.append(contentsOf: leg.advisoryNotices)
        }
        return Route(name: legs.map(\.name).filter { !$0.isEmpty }.joined(separator: " · "),
                     coordinates: coords, steps: steps, distance: total, expectedTravelTime: time,
                     calculatedAt: legs.map(\.calculatedAt).min() ?? Date(),
                     advisoryNotices: Array(Set(notices)).sorted(),
                     hasTolls: legs.contains { $0.hasTolls }, hasHighways: legs.contains { $0.hasHighways },
                     isTrafficAware: legs.allSatisfy { $0.isTrafficAware }, provider: first.provider,
                     legEndDistances: legEnds, waypoints: waypoints)
    }
}

/// Options the user can set for route calculation. Each provider reports which of these
/// it can honor; unsupported ones are shown disabled rather than silently ignored.
public struct RoutePreferences: Codable, Hashable, Sendable {
    public var avoidTolls: Bool
    public var avoidHighways: Bool
    public var avoidFerries: Bool
    public var requestAlternatives: Bool

    public init(avoidTolls: Bool = false, avoidHighways: Bool = false, avoidFerries: Bool = false, requestAlternatives: Bool = true) {
        self.avoidTolls = avoidTolls
        self.avoidHighways = avoidHighways
        self.avoidFerries = avoidFerries
        self.requestAlternatives = requestAlternatives
    }
}

public struct RouteRequest: Sendable, Hashable {
    public var origin: Waypoint
    public var stops: [Waypoint]
    public var preferences: RoutePreferences
    public var departureDate: Date

    public init(origin: Waypoint, stops: [Waypoint], preferences: RoutePreferences, departureDate: Date = Date()) {
        self.origin = origin
        self.stops = stops
        self.preferences = preferences
        self.departureDate = departureDate
    }
}

/// How routes compare against the fastest option, for the route preview list.
public struct RouteComparison: Sendable, Hashable {
    public var routeID: UUID
    public var isFastest: Bool
    public var isShortest: Bool
    public var timeDelta: TimeInterval
    public var distanceDelta: Double

    public static func compare(_ routes: [Route]) -> [RouteComparison] {
        guard let fastest = routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }),
              let shortest = routes.min(by: { $0.distance < $1.distance }) else { return [] }
        return routes.map {
            RouteComparison(routeID: $0.id, isFastest: $0.id == fastest.id, isShortest: $0.id == shortest.id,
                            timeDelta: $0.expectedTravelTime - fastest.expectedTravelTime,
                            distanceDelta: $0.distance - fastest.distance)
        }
    }
}
