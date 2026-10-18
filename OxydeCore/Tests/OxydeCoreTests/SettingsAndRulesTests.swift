import XCTest
@testable import OxydeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SettingsTests: XCTestCase {
    func testSettingsRoundTripAndTolerateMissingKeys() throws {
        var s = AppSettings()
        s.units = .imperial
        s.hiddenElements = [.compass, .speedometer]
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), s)

        let old = Data(#"{"units":"metric","zoomScale":9}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(decoded.units, .metric)
        XCTAssertEqual(decoded.zoomScale, 1.6, "clamped")
        XCTAssertEqual(decoded.defaultThemeID, ThemeRegistry.defaultThemeID)
        XCTAssertFalse(decoded.tripHistoryEnabled, "trip history must default to off")
        XCTAssertFalse(decoded.cloudSyncEnabled, "sync must default to off")
    }

    func testProfilesApplyAndReferenceRealThemes() {
        for p in DriverProfile.builtIns {
            XCTAssertNotNil(ThemeRegistry.theme(id: p.dayThemeID), p.id)
            XCTAssertNotNil(ThemeRegistry.theme(id: p.nightThemeID), p.id)
        }
        var s = AppSettings()
        DriverProfile.minimal.apply(to: &s)
        XCTAssertEqual(s.activeProfileID, "profile.minimal")
        XCTAssertEqual(s.voice.guidanceLevel, .alertsOnly)
        XCTAssertTrue(s.hiddenElements.contains(.reportButton))
        let captured = DriverProfile.capture(from: s, name: "Mine")
        XCTAssertFalse(captured.isBuiltIn)
        XCTAssertEqual(captured.hiddenElements, s.hiddenElements)
    }

    func testActiveThemeFollowsDayNight() {
        var s = AppSettings()
        s.dayNightMode = .system
        XCTAssertEqual(s.activeThemeID(nightActive: true), s.nightThemeID)
        XCTAssertEqual(s.activeThemeID(nightActive: false), s.dayThemeID)
        s.dayNightMode = .off
        XCTAssertEqual(s.activeThemeID(nightActive: true), s.defaultThemeID)
    }

    func testUnitsResolution() {
        XCTAssertEqual(UnitSystem.automatic.resolved(regionCode: "US"), .imperial)
        XCTAssertEqual(UnitSystem.automatic.resolved(regionCode: "GB"), .imperial)
        XCTAssertEqual(UnitSystem.automatic.resolved(regionCode: "RO"), .metric)
        XCTAssertEqual(UnitSystem.metric.resolved(regionCode: "US"), .metric)
    }

    func testDistanceFormatting() {
        XCTAssertEqual(DistanceFormatter.guidance(meters: 37, system: .metric).display, "40 m")
        XCTAssertEqual(DistanceFormatter.guidance(meters: 3, system: .metric).display, "10 m")
        XCTAssertEqual(DistanceFormatter.guidance(meters: 430, system: .metric).display, "450 m")
        XCTAssertEqual(DistanceFormatter.guidance(meters: 990, system: .metric).spoken, "1 kilometer")
        XCTAssertEqual(DistanceFormatter.guidance(meters: 2340, system: .metric).display, "2.3 km")
        XCTAssertEqual(DistanceFormatter.guidance(meters: 15_600, system: .metric).display, "16 km")
        XCTAssertEqual(DistanceFormatter.guidance(meters: 100, system: .imperial).display, "350 ft")
        XCTAssertEqual(DistanceFormatter.guidance(meters: 1609.344, system: .imperial).spoken, "1 mile")
        XCTAssertEqual(DistanceFormatter.guidance(meters: 5000, system: .imperial).display, "3.1 mi")
        XCTAssertEqual(SpeedFormatter.value(metersPerSecond: 27.78, system: .metric), 100)
        XCTAssertEqual(SpeedFormatter.value(metersPerSecond: 26.82, system: .imperial), 60)
        XCTAssertEqual(DurationFormatter.short(30), "< 1 min")
        XCTAssertEqual(DurationFormatter.short(14 * 60), "14 min")
        XCTAssertEqual(DurationFormatter.short(3900), "1 h 05 min")
        XCTAssertEqual(DurationFormatter.delta(240), "+4 min")
        XCTAssertEqual(DurationFormatter.delta(10), "same time")
    }

    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testSunTimesLondonMidsummer() {
        let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
        guard case let .normal(rise, set) = SolarCalculator.sunTimes(on: date("2024-06-21T12:00:00Z"), at: london) else {
            return XCTFail()
        }
        // Published times: sunrise 03:43 UTC, sunset 20:21 UTC.
        XCTAssertEqual(rise.timeIntervalSince(date("2024-06-21T03:43:00Z")), 0, accuracy: 180)
        XCTAssertEqual(set.timeIntervalSince(date("2024-06-21T20:21:00Z")), 0, accuracy: 180)
    }

    func testIsNightAcrossUTCMidnight() {
        let la = Coordinate(latitude: 34.05, longitude: -118.24)
        // 18:00 PDT on 21 June is 01:00 UTC on 22 June, still daylight.
        XCTAssertFalse(SolarCalculator.isNight(at: date("2024-06-22T01:00:00Z"), coordinate: la))
        // 23:00 PDT.
        XCTAssertTrue(SolarCalculator.isNight(at: date("2024-06-22T06:00:00Z"), coordinate: la))
        // Noon PDT.
        XCTAssertFalse(SolarCalculator.isNight(at: date("2024-06-21T19:00:00Z"), coordinate: la))
        let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
        XCTAssertEqual(SolarCalculator.sunTimes(on: date("2024-06-21T12:00:00Z"), at: tromso), .polarDay)
        XCTAssertEqual(SolarCalculator.sunTimes(on: date("2024-12-21T12:00:00Z"), at: tromso), .polarNight)
    }
}

final class ReportRulesTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)

    func report(_ c: ReportCategory = .hazard, at coord: Coordinate = Fixtures.origin, heading: Double? = nil,
                confirmations: Int = 0, dismissals: Int = 0) -> CommunityReport {
        CommunityReport(id: UUID().uuidString, category: c, coordinate: coord, heading: heading, createdAt: t0,
                        expiresAt: t0.addingTimeInterval(c.baseLifetime), confirmations: confirmations, dismissals: dismissals)
    }

    func testExpiryExtensionIsCapped() {
        let r = report(.trafficJam)
        let e1 = ReportPolicy.expiry(for: r, confirmedAt: t0.addingTimeInterval(25 * 60))
        XCTAssertEqual(e1, t0.addingTimeInterval(40 * 60))
        let late = ReportPolicy.expiry(for: r, confirmedAt: t0.addingTimeInterval(10 * 3600))
        XCTAssertEqual(late, t0.addingTimeInterval(90 * 60), "never beyond 3× base lifetime")
    }

    func testRemovalAndConfidence() {
        XCTAssertFalse(ReportPolicy.shouldRemove(report(dismissals: 1)))
        XCTAssertTrue(ReportPolicy.shouldRemove(report(dismissals: 2)))
        XCTAssertFalse(ReportPolicy.shouldRemove(report(confirmations: 3, dismissals: 3)))
        XCTAssertEqual(ReportPolicy.confidence(of: report()), .unconfirmed)
        XCTAssertEqual(ReportPolicy.confidence(of: report(confirmations: 1)), .medium)
        XCTAssertEqual(ReportPolicy.confidence(of: report(confirmations: 5)), .high)
        XCTAssertEqual(ReportPolicy.confidence(of: report(confirmations: 1, dismissals: 3)), .low)
    }

    func testDuplicateDetection() {
        let existing = report(.accident, heading: 90)
        let near = GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 80)
        let far = GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 400)
        XCTAssertEqual(ReportPolicy.duplicate(of: .accident, at: near, heading: 100, among: [existing], now: t0)?.id, existing.id)
        XCTAssertNil(ReportPolicy.duplicate(of: .accident, at: near, heading: 270, among: [existing], now: t0), "opposite carriageway")
        XCTAssertNil(ReportPolicy.duplicate(of: .accident, at: far, heading: 90, among: [existing], now: t0))
        XCTAssertNil(ReportPolicy.duplicate(of: .hazard, at: near, heading: 90, among: [existing], now: t0))
        XCTAssertNil(ReportPolicy.duplicate(of: .accident, at: near, heading: 90, among: [existing], now: t0.addingTimeInterval(7200)), "expired")
    }

    func testRegionPolicy() {
        let p = ReportRegionPolicy.conservativeDefault
        XCTAssertFalse(p.isAllowed(.speedCamera, regionCode: "DE"))
        XCTAssertTrue(p.isAllowed(.speedCamera, regionCode: "US"))
        XCTAssertFalse(p.isAllowed(.police, regionCode: "fr"))
        XCTAssertTrue(p.isAllowed(.accident, regionCode: "DE"))
        XCTAssertFalse(p.isAllowed(.police, regionCode: nil))
        XCTAssertEqual(p.allowedCategories(regionCode: "CH").count, ReportCategory.allCases.count - 2)
    }

    func testRateLimiter() {
        var limiter = RateLimiter(minimumInterval: 30, maxPerWindow: 3, window: 3600)
        XCTAssertEqual(limiter.check(at: t0), .allowed)
        limiter.record(at: t0)
        XCTAssertEqual(limiter.check(at: t0.addingTimeInterval(10)), .wait(20))
        limiter.record(at: t0.addingTimeInterval(40))
        limiter.record(at: t0.addingTimeInterval(80))
        XCTAssertEqual(limiter.check(at: t0.addingTimeInterval(200)), .wait(3400))
        XCTAssertEqual(limiter.check(at: t0.addingTimeInterval(3601)), .allowed)
    }

    func testIncidentFreshnessAndRouteMatching() {
        let box = BoundingBox(coordinates: [Fixtures.origin])!
        let snap = IncidentSnapshot(incidents: [], fetchedAt: t0, area: box, sources: [])
        XCTAssertEqual(snap.freshness(at: t0.addingTimeInterval(60)), .current)
        XCTAssertEqual(snap.freshness(at: t0.addingTimeInterval(600)), .aging)
        XCTAssertEqual(snap.freshness(at: t0.addingTimeInterval(1200)), .stale)

        let poly = MeasuredPolyline(Fixtures.lRoute().coordinates)
        let onRoute = Incident(id: "a", kind: .closure, severity: .major,
                               coordinate: GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 700),
                               title: "Closed", roadClosed: true, updatedAt: t0, source: .provider(name: "TomTom"))
        let behind = Incident(id: "b", kind: .accident, severity: .major,
                              coordinate: GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 100),
                              title: "Crash", updatedAt: t0, source: .provider(name: "TomTom"))
        let community = Incident(id: "c", kind: .hazard, severity: .minor,
                                 coordinate: GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 900),
                                 title: "Hazard", updatedAt: t0, source: .community)
        let matches = RouteIncidentMatcher.incidentsAhead(on: poly, traveled: 300, incidents: [onRoute, behind, community], includeCommunity: false)
        XCTAssertEqual(matches.map(\.incident.id), ["a"])
        XCTAssertEqual(matches.first?.distanceAhead ?? 0, 400, accuracy: 2)
        XCTAssertEqual(RouteIncidentMatcher.incidentsAhead(on: poly, traveled: 300, incidents: [onRoute, community], includeCommunity: true).count, 2)
    }
}

final class TripAndPlaceTests: XCTestCase {
    func testTripRecorderAccumulatesAndProtectsPrivacy() {
        var rec = TripRecorder(precision: .approximate, startedAt: Date(timeIntervalSince1970: 1_000_000), destinationName: "Work")
        for f in Fixtures.drive(Fixtures.lRoute(), speed: 10) { rec.add(f) }
        // Jitter and a GPS jump are ignored.
        rec.add(Fixtures.fix(GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 50_000), t: 202))
        let s = rec.finish(at: Date(timeIntervalSince1970: 1_000_210))
        XCTAssertEqual(s.distance, 2000, accuracy: 15)
        XCTAssertNil(s.encodedShape)
        XCTAssertEqual(s.start, Fixtures.origin.rounded(decimals: 3))
        XCTAssertEqual(s.averageMovingSpeed ?? 0, 10, accuracy: 0.5)

        var precise = TripRecorder(precision: .precise, startedAt: Date(timeIntervalSince1970: 1_000_000), destinationName: nil)
        for f in Fixtures.drive(Fixtures.lRoute(), speed: 10) { precise.add(f) }
        let p = precise.finish(at: Date(timeIntervalSince1970: 1_000_210))
        XCTAssertEqual(PolylineCodec.decode(p.encodedShape ?? "")?.count, 3)
    }

    func testTripRecorderRejectsInaccurateFixes() {
        var rec = TripRecorder(precision: .approximate, startedAt: Date(), destinationName: nil)
        rec.add(Fixtures.fix(Fixtures.origin, t: 0, accuracy: 200))
        rec.add(Fixtures.fix(GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 100), t: 10, accuracy: 200))
        XCTAssertEqual(rec.finish(at: Date()).distance, 0)
    }

    func testCoordinateParser() {
        XCTAssertEqual(CoordinateParser.parse("37.3349, -122.0090"), Coordinate(latitude: 37.3349, longitude: -122.009))
        XCTAssertEqual(CoordinateParser.parse("geo:48.85,2.35"), Coordinate(latitude: 48.85, longitude: 2.35))
        XCTAssertEqual(CoordinateParser.parse("37.3349 N, 122.0090 W"), Coordinate(latitude: 37.3349, longitude: -122.009))
        XCTAssertEqual(CoordinateParser.parse("33.86S 151.21E"), Coordinate(latitude: -33.86, longitude: 151.21))
        XCTAssertEqual(CoordinateParser.parse("2.35 E, 48.85 N"), Coordinate(latitude: 48.85, longitude: 2.35))
        XCTAssertNil(CoordinateParser.parse("Coffee near me"))
        XCTAssertNil(CoordinateParser.parse("95, 10"))
        XCTAssertNil(CoordinateParser.parse("12"))
    }

    func testAlongRouteRanking() {
        let poly = MeasuredPolyline(Fixtures.lRoute().coordinates)
        func place(_ id: String, along: Double, off: Double) -> Place {
            let onLine = GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: along)
            return Place(id: id, name: id, coordinate: GeoMath.destination(from: onLine, bearing: 270, distance: off), provider: "test")
        }
        let ranked = AlongRouteRanker.rank([place("behind", along: 100, off: 10), place("close", along: 500, off: 20),
                                            place("detour", along: 400, off: 900), place("far", along: 900, off: 10),
                                            place("close", along: 500, off: 20), place("away", along: 500, off: 5000)],
                                           polyline: poly, traveled: 300)
        XCTAssertEqual(ranked.map(\.place.id), ["close", "far", "detour"])
    }
}

/// Fake transport that replays canned responses, for testing retry behavior.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    var responses: [Result<HTTPResponse, Error>]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [Result<HTTPResponse, Error>]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try responses.removeFirst().get()
    }
    static func ok(_ json: String, status: Int = 200, headers: [String: String] = [:]) -> Result<HTTPResponse, Error> {
        .success(HTTPResponse(status: status, headers: headers, body: Data(json.utf8)))
    }
}

final class HTTPClientTests: XCTestCase {
    func client(_ t: ScriptedTransport) -> HTTPClient {
        HTTPClient(baseURL: URL(string: "https://api.example")!, transport: t, retry: RetryPolicy(maxAttempts: 3), sleep: { _ in })
    }

    func testRetriesServerErrorsForIdempotentRequests() async throws {
        let t = ScriptedTransport([ScriptedTransport.ok("", status: 503), ScriptedTransport.ok("{}", status: 200)])
        _ = try await client(t).send(HTTPRequest(path: "v1/x"))
        XCTAssertEqual(t.requests.count, 2)
    }

    func testDoesNotRetryUnsafePost() async {
        let t = ScriptedTransport([ScriptedTransport.ok("", status: 503), ScriptedTransport.ok("{}")])
        do {
            _ = try await client(t).send(HTTPRequest(method: "POST", path: "v1/x"))
            XCTFail()
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 503))
        }
        XCTAssertEqual(t.requests.count, 1)
    }

    func testRateLimitHonorsRetryAfter() async throws {
        let t = ScriptedTransport([ScriptedTransport.ok("", status: 429, headers: ["retry-after": "7"]), ScriptedTransport.ok("{}")])
        final class Box: @unchecked Sendable { var delays: [TimeInterval] = [] }
        let box = Box()
        var c = client(t)
        c.sleep = { (d: TimeInterval) in box.delays.append(d) }
        _ = try await c.send(HTTPRequest(path: "v1/x"))
        XCTAssertEqual(box.delays, [7])
    }

    func testClientErrorSurfacesServerMessage() async {
        let t = ScriptedTransport([ScriptedTransport.ok(#"{"error":"Too far from your location"}"#, status: 422)])
        do {
            _ = try await client(t).send(HTTPRequest(path: "v1/x"))
            XCTFail()
        } catch {
            XCTAssertEqual(error as? APIError, .client(status: 422, message: "Too far from your location"))
        }
    }

    func testRetryPolicyBackoff() {
        let p = RetryPolicy(maxAttempts: 4, baseDelay: 1, maxDelay: 5)
        XCTAssertEqual(p.delay(forAttempt: 1, retryAfter: nil, jitter: 0), 1)
        XCTAssertEqual(p.delay(forAttempt: 3, retryAfter: nil, jitter: 0), 4)
        XCTAssertEqual(p.delay(forAttempt: 5, retryAfter: nil, jitter: 0), 5)
    }

    func testBackendClientParsesIncidentsAndReports() async throws {
        let json = """
        {"generatedAt":"2026-10-18T09:00:00Z","sources":["TomTom","Oxyde community"],"incidents":[
          {"id":"tt-1","kind":"closure","severity":"major","lat":48.86,"lon":2.35,"title":"Road closed","roadClosed":true,
           "updatedAt":"2026-10-18T08:59:00Z","source":"TomTom","geometry":[[2.35,48.86],[2.36,48.87]]},
          {"id":"r-1","kind":"hazard","lat":48.85,"lon":2.34,"title":"Road hazard","updatedAt":"2026-10-18T08:58:00Z",
           "source":"Oxyde community","community":true,
           "report":{"id":"r-1","category":"hazard","lat":48.85,"lon":2.34,"createdAt":"2026-10-18T08:58:00Z",
                     "expiresAt":"2026-10-18T09:58:00Z","confirmations":2,"dismissals":0}}]}
        """
        let t = ScriptedTransport([ScriptedTransport.ok(json)])
        let backend = OxydeBackendClient(http: client(t), installID: "install-1")
        let snap = try await backend.incidents(in: BoundingBox(minLatitude: 48, minLongitude: 2, maxLatitude: 49, maxLongitude: 3))
        XCTAssertEqual(snap.incidents.count, 2)
        XCTAssertEqual(snap.incidents[0].source, IncidentSource.provider(name: "TomTom"))
        XCTAssertTrue(snap.incidents[0].roadClosed)
        XCTAssertEqual(snap.incidents[0].geometry?.last, Coordinate(latitude: 48.87, longitude: 2.36))
        XCTAssertEqual(snap.incidents[1].source, IncidentSource.community)
        XCTAssertEqual(snap.incidents[1].report?.confirmations, 2)
        XCTAssertEqual(t.requests.first?.url?.query, "bbox=2.00000,48.00000,3.00000,49.00000")
    }

    func testUnconfiguredServicesFailHonestly() async {
        do {
            _ = try await UnconfiguredIncidentService().incidents(in: BoundingBox(coordinates: [Fixtures.origin])!)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? APIError, .notConfigured("The traffic incident service"))
        }
    }

    func testFeatureCatalogReflectsConfiguration() {
        let off = FeatureCatalog.features(.init(backendConfigured: false, vectorEngineAvailable: false, storeConfigured: false))
        XCTAssertEqual(off.first { $0.id == "incidents" }?.state, .requiresConfiguration)
        let on = FeatureCatalog.features(.init(backendConfigured: true, vectorEngineAvailable: true, storeConfigured: true))
        XCTAssertEqual(on.first { $0.id == "incidents" }?.state, .implemented)
        XCTAssertEqual(on.first { $0.id == "lanes" }?.state, .providerLimited)
        XCTAssertEqual(Set(on.map(\.id)).count, on.count)
    }
}
