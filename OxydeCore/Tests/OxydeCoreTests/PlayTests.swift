import XCTest
@testable import OxydeCore

final class PlayTests: XCTestCase {
    func testExplorationRevealsEachSquareOnceAndIgnoresBadFixes() {
        var grid = ExplorationGrid()
        let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
        XCTAssertTrue(grid.record(paris, accuracy: 10))
        XCTAssertFalse(grid.record(Coordinate(latitude: 48.8567, longitude: 2.3523), accuracy: 10))
        XCTAssertFalse(grid.record(Coordinate(latitude: 48.90, longitude: 2.40), accuracy: 500))
        XCTAssertEqual(grid.count, 1)
        XCTAssertTrue(grid.record(Coordinate(latitude: 48.8666, longitude: 2.3522), accuracy: 10))
        XCTAssertEqual(grid.count, 2)

        let cell = ExplorationGrid.cell(for: paris)
        let corners = ExplorationGrid.corners(of: cell)
        XCTAssertEqual(corners.count, 4)
        XCTAssertLessThanOrEqual(corners[0].latitude, paris.latitude)
        XCTAssertGreaterThanOrEqual(corners[2].latitude, paris.latitude)
        XCTAssertLessThanOrEqual(corners[0].longitude, paris.longitude)
        XCTAssertGreaterThanOrEqual(corners[2].longitude, paris.longitude)
        // Cells stay roughly square on the ground.
        let ns = GeoMath.distance(corners[0], corners[3]), ew = GeoMath.distance(corners[0], corners[1])
        XCTAssertEqual(ns / ew, 1, accuracy: 0.05)

        let area = BoundingBox(minLatitude: 48.85, minLongitude: 2.34, maxLatitude: 48.86, maxLongitude: 2.36)
        XCTAssertEqual(grid.cells(in: area).count, 1)
        let data = try! JSONEncoder().encode(grid)
        XCTAssertEqual(try! JSONDecoder().decode(ExplorationGrid.self, from: data), grid)
        grid.erase()
        XCTAssertEqual(grid.count, 0)
    }

    func testProgressLevelsAndAchievements() {
        var p = DriverProgress()
        XCTAssertEqual(p.level, 1)
        XCTAssertEqual(p.rank, "Rookie")
        for _ in 0..<10 { p.apply(.drove(meters: 50, atNight: false)) }
        XCTAssertEqual(p.xp, 5)
        let unlocked = p.apply(.arrived)
        XCTAssertEqual(unlocked.map(\.id), ["first-arrival"])
        XCTAssertEqual(p.xp, 5 + 25 + 50)
        XCTAssertTrue(p.apply(.arrived).isEmpty, "an achievement unlocks once")
        // Implausible jumps (GPS glitches) earn nothing.
        let before = p.xp
        p.apply(.drove(meters: 80_000, atNight: false))
        XCTAssertEqual(p.xp, before)
        for i in 0..<5 { p.apply(.themeApplied(id: "t\(i)")) }
        XCTAssertTrue(p.isUnlocked(DriverProgress.achievements.first { $0.id == "stylist" }!))
        XCTAssertGreaterThanOrEqual(p.level, 2)
        XCTAssertEqual(DriverProgress.threshold(forLevel: 2), 100)
        XCTAssertEqual(DriverProgress.threshold(forLevel: 4), 600)
        XCTAssertTrue((0...1).contains(p.levelProgress))
    }

    func testNoAchievementRewardsSpeed() {
        for a in DriverProgress.achievements {
            let text = (a.id + a.title + a.detail).lowercased()
            for word in ["speed", "fast", "quick", "km/h", "mph", "race"] {
                XCTAssertFalse(text.contains(word), "\(a.id) mentions \(word)")
            }
        }
    }

    func testConvoyCodes() {
        let code = ConvoyCode.random()
        XCTAssertEqual(code.count, 6)
        XCTAssertEqual(ConvoyCode.normalize(code), code)
        XCTAssertEqual(ConvoyCode.normalize(" abc-def "), "ABCDEF")
        XCTAssertNil(ConvoyCode.normalize("ABCDE0"), "0 is not in the alphabet")
        XCTAssertNil(ConvoyCode.normalize("ABC"))
    }

    func testConvoyClientDecodesMembers() async throws {
        let json = """
        {"code":"ABCDEF","name":"Weekend","expiresAt":"2026-10-18T20:00:00Z","destination":[2.35,48.85],"destinationName":"Paris",
         "members":[{"id":"m1","name":"Ana","color":"#7C4DFF","lat":48.8,"lon":2.3,"heading":90,"updatedAt":"2026-10-18T12:00:00Z","me":true},
                    {"id":"m2","name":"Dan","color":"#5AD39A"}]}
        """
        let transport = ScriptedTransport([ScriptedTransport.ok(json)])
        let http = HTTPClient(baseURL: URL(string: "https://api.example")!, transport: transport, retry: .none)
        let client = OxydeBackendClient(http: http, installID: "install-1234")
        let snap = try await client.update(code: "ABCDEF", coordinate: Coordinate(latitude: 48.8, longitude: 2.3), heading: 90)
        XCTAssertEqual(snap.members.count, 2)
        XCTAssertTrue(snap.members[0].isMe)
        XCTAssertEqual(snap.members[0].coordinate?.latitude, 48.8)
        XCTAssertNil(snap.members[1].coordinate)
        XCTAssertTrue(snap.members[1].isStale())
        XCTAssertEqual(snap.destination?.longitude, 2.35)
        XCTAssertEqual(transport.requests.first?.httpMethod, "PUT")
        XCTAssertEqual(transport.requests.first?.url?.path, "/v1/convoys/ABCDEF/members/me/position")
    }
}
