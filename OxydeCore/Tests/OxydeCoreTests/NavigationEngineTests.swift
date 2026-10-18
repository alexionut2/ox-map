import XCTest
@testable import OxydeCore

final class NavigationEngineTests: XCTestCase {
    func makeEngine(_ route: Route = Fixtures.lRoute(), level: GuidanceLevel = .full) -> NavigationEngine {
        NavigationEngine(route: route, scheduler: GuidanceScheduler(level: level, units: .metric))
    }

    func testFullDriveProducesOrderedGuidanceAndArrival() {
        let route = Fixtures.lRoute()
        var engine = makeEngine(route)
        var announcements: [Announcement] = []
        var stepChanges: [Int] = []
        var arrived = false
        var lastRemaining = Double.infinity
        for fix in Fixtures.drive(route) {
            for e in engine.update(with: fix) {
                switch e {
                case .announce(let a): announcements.append(a)
                case .stepAdvanced(let s): stepChanges.append(s)
                case .arrived: arrived = true
                case .progress(let p):
                    XCTAssertLessThanOrEqual(p.distanceRemaining, lastRemaining + 0.001)
                    lastRemaining = p.distanceRemaining
                case .offRoute: XCTFail("Driving exactly on the route must never go off route")
                default: break
                }
            }
        }
        XCTAssertTrue(arrived)
        // Arrival fires within the arrival radius, before the final step is reached.
        XCTAssertEqual(stepChanges, [1])
        let texts = announcements.map(\.text)
        XCTAssertEqual(texts.first, "In 1 kilometer, turn right onto Example Avenue")
        XCTAssertTrue(texts.contains("In 400 meters, turn right onto Example Avenue"))
        XCTAssertTrue(texts.contains("Turn right onto Example Avenue"))
        XCTAssertEqual(announcements.last?.stage, .arrival)
        XCTAssertEqual(announcements.last?.text, "Arrive at the destination")
        // Each stage is spoken once per maneuver.
        XCTAssertEqual(Set(texts).count, texts.count, "\(texts)")
    }

    func testProgressValuesMidRoute() {
        let route = Fixtures.lRoute()
        var engine = makeEngine(route)
        let c = GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 600)
        let events = engine.update(with: Fixtures.fix(c, t: 0, course: 0))
        guard case .progress(let p)? = events.first(where: { if case .progress = $0 { return true } else { return false } }) else {
            return XCTFail("no progress")
        }
        XCTAssertEqual(p.distanceTraveled, 600, accuracy: 2)
        XCTAssertEqual(p.distanceRemaining, 1400, accuracy: 2)
        XCTAssertEqual(p.upcomingStepIndex, 1)
        XCTAssertEqual(p.distanceToUpcomingManeuver ?? 0, 400, accuracy: 2)
        XCTAssertEqual(p.followingStepIndex, 2)
        // 240 s for 2000 m from the provider, 1400 m left.
        XCTAssertEqual(p.timeRemaining, 168, accuracy: 1)
    }

    func testOffRouteNeedsSustainedDeviation() {
        var engine = makeEngine()
        let base = GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 300)
        _ = engine.update(with: Fixtures.fix(base, t: 0, course: 0))
        // One wild fix: suspect, not off-route.
        let off = GeoMath.destination(from: base, bearing: 270, distance: 120)
        XCTAssertFalse(engine.update(with: Fixtures.fix(off, t: 1)).contains(.offRoute(.leftRoute)))
        // Back on route resets the count.
        _ = engine.update(with: Fixtures.fix(base, t: 2, course: 0))
        var events: [NavigationEvent] = []
        for i in 0..<6 {
            let p = GeoMath.destination(from: base, bearing: 270, distance: 100 + Double(i) * 15)
            events += engine.update(with: Fixtures.fix(p, t: 3 + Double(i), course: 270))
        }
        XCTAssertTrue(events.contains(.offRoute(.leftRoute)))
    }

    func testInaccurateFixesAreIgnoredForRerouting() {
        var engine = makeEngine()
        let far = GeoMath.destination(from: Fixtures.origin, bearing: 270, distance: 300)
        var events: [NavigationEvent] = []
        for i in 0..<10 { events += engine.update(with: Fixtures.fix(far, t: Double(i), accuracy: 200)) }
        XCTAssertFalse(events.contains(.offRoute(.leftRoute)))
        XCTAssertEqual(events.filter { $0 == .weakSignal }.count, 1)
    }

    func testWrongWayDetection() {
        var engine = makeEngine()
        var events: [NavigationEvent] = []
        for i in 0..<6 {
            let c = GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 800 - Double(i) * 14)
            events += engine.update(with: Fixtures.fix(c, t: Double(i), speed: 14, course: 180))
        }
        XCTAssertTrue(events.contains(.offRoute(.wrongDirection)))
    }

    func testSignalLossTick() {
        var engine = makeEngine()
        _ = engine.update(with: Fixtures.fix(Fixtures.origin, t: 0))
        XCTAssertEqual(engine.tick(now: Date(timeIntervalSince1970: 1_000_005)), [])
        XCTAssertEqual(engine.tick(now: Date(timeIntervalSince1970: 1_000_011)), [.signalLost])
        XCTAssertEqual(engine.tick(now: Date(timeIntervalSince1970: 1_000_012)), [])
        let back = engine.update(with: Fixtures.fix(Fixtures.origin, t: 13))
        XCTAssertTrue(back.contains(.signalRecovered))
    }

    func testTravelTimeRefreshRescalesETA() {
        var engine = makeEngine()
        let c = GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 1000)
        _ = engine.update(with: Fixtures.fix(c, t: 0, course: 0))
        engine.applyTravelTimeRefresh(300, at: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(engine.progress?.timeRemaining ?? 0, 300, accuracy: 0.1)
        let further = GeoMath.destination(from: c, bearing: 90, distance: 500)
        _ = engine.update(with: Fixtures.fix(further, t: 30, course: 90))
        // Half of the remaining 1000 m left → half of the refreshed 300 s.
        XCTAssertEqual(engine.progress?.timeRemaining ?? 0, 150, accuracy: 2)
    }

    func testMultiStopArrivalAtWaypoint() {
        let leg = Fixtures.lRoute()
        var back = leg
        back.coordinates = leg.coordinates.reversed()
        back.steps = [
            RouteStep(id: 0, instruction: "Head west", distance: 1000, startIndex: 0, maneuver: .depart),
            RouteStep(id: 1, instruction: "Turn left onto Test Street", distance: 1000, startIndex: leg.steps[1].startIndex, maneuver: .left),
            RouteStep(id: 2, instruction: "Arrive at the destination", distance: 0, startIndex: leg.coordinates.count - 1, maneuver: .arrive),
        ]
        let stop = Waypoint(name: "Bakery", coordinate: leg.coordinates.last!)
        let route = Route.combining(legs: [leg, back], waypoints: [Waypoint(name: "Start", coordinate: Fixtures.origin), stop,
                                                                   Waypoint(name: "Home", coordinate: Fixtures.origin)])!
        var engine = makeEngine(route)
        var waypointEvents: [Waypoint] = []
        var spoken: [String] = []
        var arrived = false
        for fix in Fixtures.drive(route) {
            for e in engine.update(with: fix) {
                if case .arrivedAtWaypoint(_, let w) = e { waypointEvents.append(w) }
                if case .announce(let a) = e { spoken.append(a.text) }
                if case .arrived = e { arrived = true }
            }
        }
        XCTAssertEqual(waypointEvents.map(\.name), ["Bakery"])
        XCTAssertTrue(spoken.contains("You have reached Bakery."))
        XCTAssertTrue(arrived)
    }

    func testReplaceRouteResetsGuidance() {
        var engine = makeEngine()
        _ = engine.update(with: Fixtures.fix(GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 100), t: 0, course: 0))
        var newRoute = Fixtures.lRoute()
        newRoute.id = UUID()
        engine.replaceRoute(newRoute)
        XCTAssertNil(engine.progress)
        let events = engine.update(with: Fixtures.fix(GeoMath.destination(from: Fixtures.origin, bearing: 0, distance: 120), t: 1, course: 0))
        XCTAssertTrue(events.contains { if case .announce = $0 { return true } else { return false } })
    }
}

final class GuidanceSchedulerTests: XCTestCase {
    func progress(distanceToManeuver: Double, upcoming: Int = 1, following: Int? = 2, gap: Double? = 1000) -> RouteProgress {
        RouteProgress(routeID: UUID(), snappedCoordinate: Fixtures.origin, routeBearing: 0, distanceTraveled: 0,
                      distanceRemaining: 2000, distanceRemainingInLeg: 2000, legIndex: 0, currentStepIndex: upcoming - 1,
                      upcomingStepIndex: upcoming, distanceToUpcomingManeuver: distanceToManeuver,
                      followingStepIndex: following, distanceFromUpcomingToFollowing: gap, timeRemaining: 100,
                      estimatedArrival: Date(), travelTimeUpdatedAt: Date(), offset: 0, fixAccuracy: 5)
    }

    func testMutedSpeaksNothing() {
        var s = GuidanceScheduler(level: .muted, units: .metric)
        XCTAssertNil(s.next(for: progress(distanceToManeuver: 50), route: Fixtures.lRoute(), speed: 10))
    }

    func testAlertsOnlySpeaksOnlyImminent() {
        var s = GuidanceScheduler(level: .alertsOnly, units: .metric)
        let route = Fixtures.lRoute()
        XCTAssertNil(s.next(for: progress(distanceToManeuver: 900), route: route, speed: 14))
        XCTAssertNil(s.next(for: progress(distanceToManeuver: 350), route: route, speed: 14))
        XCTAssertEqual(s.next(for: progress(distanceToManeuver: 70), route: route, speed: 14)?.stage, .imminent)
        XCTAssertNil(s.next(for: progress(distanceToManeuver: 40), route: route, speed: 14))
    }

    func testNeverSpeaksEmptyInstruction() {
        var route = Fixtures.lRoute()
        route.steps[1].instruction = "  "
        var s = GuidanceScheduler(level: .full, units: .metric)
        XCTAssertNil(s.next(for: progress(distanceToManeuver: 50), route: route, speed: 10))
    }

    func testChainsCloseManeuvers() {
        var route = Fixtures.lRoute()
        route.steps[2].instruction = "Turn left onto Short Lane"
        var s = GuidanceScheduler(level: .full, units: .metric)
        _ = s.next(for: progress(distanceToManeuver: 5000, gap: 80), route: route, speed: 10)
        let a = s.next(for: progress(distanceToManeuver: 30, gap: 80), route: route, speed: 10)
        XCTAssertEqual(a?.text, "Turn right onto Example Avenue, then turn left onto Short Lane")
        XCTAssertEqual(a?.interrupts, true)
    }

    func testImperialPhrasing() {
        var s = GuidanceScheduler(level: .full, units: .imperial)
        let a = s.next(for: progress(distanceToManeuver: 804.672), route: Fixtures.lRoute(), speed: 14)
        XCTAssertEqual(a?.text, "In half a mile, turn right onto Example Avenue")
    }

    func testThresholdsScaleWithSpeed() {
        let city = GuidanceScheduler.thresholds(forSpeed: 12)
        let highway = GuidanceScheduler.thresholds(forSpeed: 30)
        XCTAssertGreaterThan(highway.prepare, city.prepare)
        XCTAssertGreaterThan(highway.imminent, city.imminent)
    }

    func testLowercasingFirst() {
        XCTAssertEqual(GuidancePhrasebook.lowercasingFirst("Turn right"), "turn right")
        XCTAssertEqual(GuidancePhrasebook.lowercasingFirst("I-280 S"), "I-280 S")
        XCTAssertEqual(GuidancePhrasebook.lowercasingFirst("US 101"), "US 101")
        XCTAssertEqual(GuidancePhrasebook.lowercasingFirst("A9"), "A9")
    }
}
