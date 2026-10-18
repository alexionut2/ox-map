import Foundation

public enum IncidentKind: String, Codable, Sendable, CaseIterable {
    case accident, congestion, roadworks, closure, laneClosure, hazard, weather, event, police, speedCamera, other
}

public enum IncidentSeverity: String, Codable, Sendable, Comparable, CaseIterable {
    case unknown, minor, moderate, major, critical
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

public enum IncidentSource: Codable, Hashable, Sendable {
    /// An authorized traffic data provider (e.g. TomTom, HERE, a road authority feed).
    case provider(name: String)
    /// Oxyde Map drivers. Never presented as verified.
    case community

    public var isVerifiedProvider: Bool {
        if case .provider = self { return true }
        return false
    }

    public var attribution: String {
        switch self {
        case .provider(let name): return name
        case .community: return "Reported by drivers"
        }
    }
}

public struct Incident: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: IncidentKind
    public var severity: IncidentSeverity
    public var coordinate: Coordinate
    /// The affected stretch of road, when the provider supplies one.
    public var geometry: [Coordinate]?
    public var title: String
    public var detail: String?
    public var roadClosed: Bool
    public var delaySeconds: TimeInterval?
    public var startTime: Date?
    public var endTime: Date?
    public var updatedAt: Date
    public var source: IncidentSource
    /// For community reports: the report backing this incident.
    public var report: CommunityReport?

    public init(id: String, kind: IncidentKind, severity: IncidentSeverity, coordinate: Coordinate,
                geometry: [Coordinate]? = nil, title: String, detail: String? = nil, roadClosed: Bool = false,
                delaySeconds: TimeInterval? = nil, startTime: Date? = nil, endTime: Date? = nil,
                updatedAt: Date, source: IncidentSource, report: CommunityReport? = nil) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.coordinate = coordinate
        self.geometry = geometry
        self.title = title
        self.detail = detail
        self.roadClosed = roadClosed
        self.delaySeconds = delaySeconds
        self.startTime = startTime
        self.endTime = endTime
        self.updatedAt = updatedAt
        self.source = source
        self.report = report
    }
}

/// A set of incidents with the time it was fetched, so the UI can say how fresh it is
/// and never show stale data as current.
public struct IncidentSnapshot: Sendable, Equatable {
    public var incidents: [Incident]
    public var fetchedAt: Date
    public var area: BoundingBox
    public var sources: [String]

    public init(incidents: [Incident], fetchedAt: Date, area: BoundingBox, sources: [String]) {
        self.incidents = incidents
        self.fetchedAt = fetchedAt
        self.area = area
        self.sources = sources
    }

    public enum Freshness: Equatable, Sendable { case current, aging, stale }

    /// Up to 5 minutes is current, up to 15 aging, older is stale and hidden from routing decisions.
    public func freshness(at now: Date) -> Freshness {
        let age = now.timeIntervalSince(fetchedAt)
        if age <= 5 * 60 { return .current }
        if age <= 15 * 60 { return .aging }
        return .stale
    }
}

public struct RouteIncidentMatch: Sendable, Equatable {
    public var incident: Incident
    public var distanceAhead: Double
}

public enum RouteIncidentMatcher {
    /// Incidents lying on the remaining part of the route, nearest first. Only fresh data
    /// is considered, and community reports are included only if asked for.
    public static func incidentsAhead(on polyline: MeasuredPolyline, traveled: Double, incidents: [Incident],
                                      corridor: Double = 40, includeCommunity: Bool) -> [RouteIncidentMatch] {
        incidents.compactMap { inc in
            if !includeCommunity, !inc.source.isVerifiedProvider { return nil }
            guard let snap = polyline.snap(inc.coordinate), snap.offset <= corridor,
                  snap.distanceAlong > traveled else { return nil }
            return RouteIncidentMatch(incident: inc, distanceAhead: snap.distanceAlong - traveled)
        }
        .sorted { $0.distanceAhead < $1.distanceAhead }
    }
}
