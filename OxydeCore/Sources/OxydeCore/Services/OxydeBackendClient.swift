import Foundation

/// Client for the Oxyde backend (see `backend/` and docs/BACKEND.md). The backend
/// aggregates authorized traffic incident feeds and stores community reports; provider
/// API keys live on the server, never in the app.
public struct OxydeBackendClient: IncidentService, CommunityReportService {
    let http: HTTPClient
    /// A random per-install identifier used for rate limiting and vote de-duplication.
    /// It is not linked to the user's identity.
    let installID: String

    public init(baseURL: URL, installID: String, transport: HTTPTransport = URLSessionTransport(),
                retry: RetryPolicy = RetryPolicy()) {
        self.http = HTTPClient(baseURL: baseURL, transport: transport, retry: retry,
                               defaultHeaders: ["X-Oxyde-Install": installID])
        self.installID = installID
    }

    init(http: HTTPClient, installID: String) {
        self.http = http
        self.installID = installID
    }

    public var sourceDescription: String { "Oxyde backend (\(http.baseURL.host ?? "configured"))" }
    public var isConfigured: Bool { true }

    // MARK: DTOs

    struct IncidentDTO: Decodable {
        var id: String
        var kind: IncidentKind
        var severity: IncidentSeverity?
        var lat: Double
        var lon: Double
        var geometry: [[Double]]?
        var title: String
        var detail: String?
        var roadClosed: Bool?
        var delaySeconds: Double?
        var startTime: Date?
        var endTime: Date?
        var updatedAt: Date
        var source: String
        var community: Bool?
        var report: ReportDTO?
    }

    struct ReportDTO: Codable {
        var id: String
        var category: ReportCategory
        var lat: Double
        var lon: Double
        var heading: Double?
        var createdAt: Date
        var expiresAt: Date
        var confirmations: Int
        var dismissals: Int
        var note: String?

        var model: CommunityReport {
            CommunityReport(id: id, category: category, coordinate: Coordinate(latitude: lat, longitude: lon),
                            heading: heading, createdAt: createdAt, expiresAt: expiresAt,
                            confirmations: confirmations, dismissals: dismissals, note: note)
        }
    }

    struct IncidentsResponse: Decodable {
        var generatedAt: Date
        var sources: [String]
        var incidents: [IncidentDTO]
    }

    struct ReportsResponse: Decodable { var reports: [ReportDTO] }

    struct SubmitBody: Encodable {
        var category: ReportCategory
        var lat: Double
        var lon: Double
        var heading: Double?
        var reportedAt: Date
        var note: String?
    }

    struct VoteBody: Encodable { var vote: ReportVote }
    struct VoteResponse: Decodable { var report: ReportDTO?; var removed: Bool? }

    // MARK: IncidentService

    public func incidents(in area: BoundingBox) async throws -> IncidentSnapshot {
        let r = HTTPRequest(path: "v1/incidents", query: [URLQueryItem(name: "bbox", value: area.queryValue)])
        let response = try await http.decode(IncidentsResponse.self, from: r)
        let incidents = response.incidents.map { d -> Incident in
            Incident(id: d.id, kind: d.kind, severity: d.severity ?? .unknown,
                     coordinate: Coordinate(latitude: d.lat, longitude: d.lon),
                     geometry: d.geometry?.compactMap { $0.count == 2 ? Coordinate(latitude: $0[1], longitude: $0[0]) : nil },
                     title: d.title, detail: d.detail, roadClosed: d.roadClosed ?? false, delaySeconds: d.delaySeconds,
                     startTime: d.startTime, endTime: d.endTime, updatedAt: d.updatedAt,
                     source: (d.community ?? false) ? .community : .provider(name: d.source),
                     report: d.report?.model)
        }
        return IncidentSnapshot(incidents: incidents, fetchedAt: response.generatedAt, area: area, sources: response.sources)
    }

    // MARK: CommunityReportService

    public func submit(_ report: NewReport) async throws -> CommunityReport {
        let body = try HTTPClient.makeEncoder().encode(SubmitBody(
            category: report.category, lat: report.coordinate.latitude, lon: report.coordinate.longitude,
            heading: report.heading, reportedAt: report.reportedAt, note: report.note))
        // Submissions carry an idempotency key so a retried POST cannot create two reports.
        let r = HTTPRequest(method: "POST", path: "v1/reports", body: body,
                            headers: ["Idempotency-Key": UUID().uuidString], isIdempotent: true)
        return try await http.decode(ReportDTO.self, from: r).model
    }

    public func vote(_ vote: ReportVote, on reportID: String) async throws -> CommunityReport? {
        let body = try HTTPClient.makeEncoder().encode(VoteBody(vote: vote))
        let r = HTTPRequest(method: "POST", path: "v1/reports/\(reportID)/votes", body: body, isIdempotent: true)
        return try await http.decode(VoteResponse.self, from: r).report?.model
    }

    public func reports(in area: BoundingBox) async throws -> [CommunityReport] {
        let r = HTTPRequest(path: "v1/reports", query: [URLQueryItem(name: "bbox", value: area.queryValue)])
        return try await http.decode(ReportsResponse.self, from: r).reports.map(\.model)
    }
}
