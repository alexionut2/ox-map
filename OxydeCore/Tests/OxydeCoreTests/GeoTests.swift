import XCTest
@testable import OxydeCore

final class GeoTests: XCTestCase {
    func testHaversineParisLondon() {
        let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
        let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
        XCTAssertEqual(GeoMath.distance(paris, london) / 1000, 343.5, accuracy: 1.5)
    }

    func testBearingCardinal() {
        let a = Coordinate(latitude: 0.0001, longitude: 0)
        XCTAssertEqual(GeoMath.bearing(from: a, to: Coordinate(latitude: 1, longitude: 0)), 0, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: a, to: Coordinate(latitude: 0.0001, longitude: 1)), 90, accuracy: 0.1)
    }

    func testAngleDifferenceWraps() {
        XCTAssertEqual(GeoMath.angleDifference(from: 350, to: 10), 20)
        XCTAssertEqual(GeoMath.angleDifference(from: 10, to: 350), -20)
        XCTAssertEqual(abs(GeoMath.angleDifference(from: 0, to: 180)), 180)
    }

    func testDestinationRoundTrip() {
        let start = Fixtures.origin
        let d = GeoMath.destination(from: start, bearing: 45, distance: 5000)
        XCTAssertEqual(GeoMath.distance(start, d), 5000, accuracy: 1)
        XCTAssertEqual(GeoMath.bearing(from: start, to: d), 45, accuracy: 0.1)
    }

    func testCoordinateValidityAndRounding() {
        XCTAssertFalse(Coordinate(latitude: 0, longitude: 0).isValid)
        XCTAssertFalse(Coordinate(latitude: 91, longitude: 0).isValid)
        XCTAssertTrue(Fixtures.origin.isValid)
        let r = Coordinate(latitude: 48.856614, longitude: 2.352222).rounded(decimals: 3)
        XCTAssertEqual(r.latitude, 48.857, accuracy: 1e-9)
        XCTAssertEqual(r.longitude, 2.352, accuracy: 1e-9)
    }

    func testBoundingBoxExpandAndQuery() {
        let box = BoundingBox(coordinates: [Fixtures.origin])!.expanded(byMeters: 1000)
        XCTAssertTrue(box.contains(GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 900)))
        XCTAssertFalse(box.contains(GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 1200)))
        XCTAssertEqual(box.queryValue.split(separator: ",").count, 4)
    }

    func testPolylineSnapAndMeasure() {
        let route = Fixtures.lRoute()
        let poly = MeasuredPolyline(route.coordinates)
        XCTAssertEqual(poly.length, 2000, accuracy: 2)
        let offRoute = GeoMath.destination(from: GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 500), bearing: 270, distance: 20)
        let snap = poly.snap(offRoute)!
        XCTAssertEqual(snap.distanceAlong, 500, accuracy: 2)
        XCTAssertEqual(snap.offset, 20, accuracy: 1)
        XCTAssertEqual(snap.segmentBearing, 0, accuracy: 1)
    }

    func testPolylineSplit() {
        let poly = MeasuredPolyline(Fixtures.lRoute().coordinates)
        let (traveled, remaining) = poly.split(atDistance: 1200)
        XCTAssertEqual(MeasuredPolyline(traveled).length, 1200, accuracy: 2)
        XCTAssertEqual(MeasuredPolyline(remaining).length, 800, accuracy: 2)
    }

    func testSamples() {
        let poly = MeasuredPolyline(Fixtures.lRoute().coordinates)
        let s = poly.samples(every: 500, from: 100)
        XCTAssertEqual(s.map { Int($0.distance) }, [100, 600, 1100, 1600])
    }

    func testPolylineCodecKnownVector() {
        // Example from Google's encoded polyline documentation.
        let decoded = PolylineCodec.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")!
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].latitude, 38.5, accuracy: 1e-5)
        XCTAssertEqual(decoded[0].longitude, -120.2, accuracy: 1e-5)
        XCTAssertEqual(decoded[2].latitude, 43.252, accuracy: 1e-5)
        XCTAssertEqual(decoded[2].longitude, -126.453, accuracy: 1e-5)
        XCTAssertEqual(PolylineCodec.encode(decoded), "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertNil(PolylineCodec.decode("_p~iF~ps|U_"))
    }

    func testSimplifierKeepsCornerDropsCollinear() {
        let coords = Fixtures.lRoute().coordinates
        let simplified = PolylineSimplifier.simplify(coords, tolerance: 5)
        XCTAssertEqual(simplified.count, 3)
        XCTAssertEqual(simplified.first, coords.first)
        XCTAssertEqual(simplified.last, coords.last)
    }

    func testManeuverClassifierFromGeometry() {
        let route = Fixtures.lRoute()
        let corner = route.steps[1].startIndex
        XCTAssertEqual(ManeuverClassifier.classify(coordinates: route.coordinates, at: corner, instruction: "Turn onto Example Avenue",
                                                   isFirst: false, isLast: false), .right)
        let mirrored = route.coordinates.map { Coordinate(latitude: $0.latitude, longitude: 2 * Fixtures.origin.longitude - $0.longitude) }
        XCTAssertEqual(ManeuverClassifier.classify(coordinates: mirrored, at: corner, instruction: "Turn",
                                                   isFirst: false, isLast: false), .left)
        XCTAssertEqual(ManeuverClassifier.classify(coordinates: route.coordinates, at: 10, instruction: "Continue",
                                                   isFirst: false, isLast: false), .straight)
        XCTAssertEqual(ManeuverClassifier.classify(coordinates: route.coordinates, at: corner, instruction: "At the roundabout, take the 2nd exit",
                                                   isFirst: false, isLast: false), .roundabout)
        XCTAssertEqual(ManeuverClassifier.kind(forAngle: 175), .uTurn)
        XCTAssertEqual(ManeuverClassifier.kind(forAngle: -30), .slightLeft)
        XCTAssertEqual(ManeuverClassifier.kind(forAngle: 150), .sharpRight)
    }

    func testRouteCombiningLegs() {
        let a = Fixtures.lRoute()
        var b = Fixtures.lRoute()
        b.expectedTravelTime = 100
        let wps = [Waypoint(name: "A", coordinate: Fixtures.origin), Waypoint(name: "B", coordinate: Fixtures.origin),
                   Waypoint(name: "C", coordinate: Fixtures.origin)]
        let combined = Route.combining(legs: [a, b], waypoints: wps)!
        XCTAssertEqual(combined.distance, 4000)
        XCTAssertEqual(combined.expectedTravelTime, 340)
        XCTAssertEqual(combined.legEndDistances, [2000, 4000])
        XCTAssertEqual(combined.coordinates.count, a.coordinates.count * 2 - 1)
        XCTAssertEqual(combined.steps.count, 6)
        XCTAssertEqual(combined.steps[2].maneuver, .waypoint)
        XCTAssertEqual(combined.steps[5].maneuver, .arrive)
        XCTAssertEqual(combined.steps[3].startIndex, a.coordinates.count - 1)
        XCTAssertEqual(combined.steps.map(\.id), Array(0..<6))
    }

    func testRouteComparison() {
        var slow = Fixtures.lRoute()
        slow.expectedTravelTime = 400
        slow.distance = 1800
        let fast = Fixtures.lRoute()
        let cmp = RouteComparison.compare([fast, slow])
        XCTAssertTrue(cmp[0].isFastest)
        XCTAssertTrue(cmp[1].isShortest)
        XCTAssertEqual(cmp[1].timeDelta, 160)
    }
}
