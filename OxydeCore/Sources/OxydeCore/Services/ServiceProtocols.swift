import Foundation

/// What a routing provider can do. The UI reads this instead of assuming.
public struct RoutingCapabilities: Sendable, Equatable {
    public var providerName: String
    public var supportsAlternatives: Bool
    public var supportsAvoidTolls: Bool
    public var supportsAvoidHighways: Bool
    public var supportsAvoidFerries: Bool
    public var supportsMultipleStops: Bool
    public var supportsTravelTimeRefresh: Bool
    public var providesLaneGuidance: Bool
    public var providesSpeedLimits: Bool
    public var trafficAwareTravelTimes: Bool

    public init(providerName: String, supportsAlternatives: Bool, supportsAvoidTolls: Bool, supportsAvoidHighways: Bool,
                supportsAvoidFerries: Bool, supportsMultipleStops: Bool, supportsTravelTimeRefresh: Bool,
                providesLaneGuidance: Bool, providesSpeedLimits: Bool, trafficAwareTravelTimes: Bool) {
        self.providerName = providerName
        self.supportsAlternatives = supportsAlternatives
        self.supportsAvoidTolls = supportsAvoidTolls
        self.supportsAvoidHighways = supportsAvoidHighways
        self.supportsAvoidFerries = supportsAvoidFerries
        self.supportsMultipleStops = supportsMultipleStops
        self.supportsTravelTimeRefresh = supportsTravelTimeRefresh
        self.providesLaneGuidance = providesLaneGuidance
        self.providesSpeedLimits = providesSpeedLimits
        self.trafficAwareTravelTimes = trafficAwareTravelTimes
    }
}

public protocol RoutingService: Sendable {
    var capabilities: RoutingCapabilities { get }
    /// Routes for the request, best first. Throws rather than returning invented routes.
    func routes(for request: RouteRequest) async throws -> [Route]
    /// Fresh travel time from `origin` to `destination`, for ETA updates while driving.
    func travelTime(from origin: Coordinate, to destination: Coordinate, preferences: RoutePreferences) async throws -> TimeInterval
}

public struct SearchRegion: Sendable, Hashable {
    public var center: Coordinate
    public var radius: Double
    public init(center: Coordinate, radius: Double) {
        self.center = center
        self.radius = radius
    }
}

public protocol PlaceSearchService: Sendable {
    func search(text: String, near region: SearchRegion?) async throws -> [Place]
    func search(category: PlaceCategory, near region: SearchRegion) async throws -> [Place]
    func reverseGeocode(_ coordinate: Coordinate) async throws -> Place
}

public protocol IncidentService: Sendable {
    var sourceDescription: String { get }
    var isConfigured: Bool { get }
    func incidents(in area: BoundingBox) async throws -> IncidentSnapshot
}

public struct NewReport: Codable, Sendable, Equatable {
    public var category: ReportCategory
    public var coordinate: Coordinate
    public var heading: Double?
    public var reportedAt: Date
    public var note: String?

    public init(category: ReportCategory, coordinate: Coordinate, heading: Double?, reportedAt: Date, note: String? = nil) {
        self.category = category
        self.coordinate = coordinate
        self.heading = heading
        self.reportedAt = reportedAt
        self.note = note
    }
}

public enum ReportVote: String, Codable, Sendable { case confirm, dismiss }

public protocol CommunityReportService: Sendable {
    var isConfigured: Bool { get }
    func submit(_ report: NewReport) async throws -> CommunityReport
    func vote(_ vote: ReportVote, on reportID: String) async throws -> CommunityReport?
    func reports(in area: BoundingBox) async throws -> [CommunityReport]
}

/// Used when no backend URL is configured: every call fails with `.notConfigured` so the
/// UI shows setup guidance instead of fake data.
public struct UnconfiguredIncidentService: IncidentService {
    public init() {}
    public var sourceDescription: String { "Not configured" }
    public var isConfigured: Bool { false }
    public func incidents(in area: BoundingBox) async throws -> IncidentSnapshot {
        throw APIError.notConfigured("The traffic incident service")
    }
}

public struct UnconfiguredReportService: CommunityReportService {
    public init() {}
    public var isConfigured: Bool { false }
    public func submit(_ report: NewReport) async throws -> CommunityReport { throw APIError.notConfigured("Community reporting") }
    public func vote(_ vote: ReportVote, on reportID: String) async throws -> CommunityReport? { throw APIError.notConfigured("Community reporting") }
    public func reports(in area: BoundingBox) async throws -> [CommunityReport] { throw APIError.notConfigured("Community reporting") }
}
