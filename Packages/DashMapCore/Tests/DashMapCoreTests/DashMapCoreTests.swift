import XCTest
@testable import DashMapCore

final class DashMapCoreTests: XCTestCase {
    // ~111 m per 0.001° of latitude; a straight northbound route with a right turn after the first 1.1 km.
    private func makeRoute() -> Route {
        var pts = (0...10).map { Coordinate(latitude: 40 + Double($0) * 0.001, longitude: -100) }
        pts += (1...10).map { Coordinate(latitude: 40.010, longitude: -100 + Double($0) * 0.001 * 1.3) }
        let len = Route(polyline: pts, steps: [], duration: 0)!.distance
        let first = Geo.distance(pts[0], pts[10])
        return Route(
            polyline: pts,
            steps: [
                RouteStep(instruction: "Head north", maneuver: .straight, distance: first, duration: 60),
                RouteStep(instruction: "Turn right onto Elm St", maneuver: .turnRight, distance: len - first, duration: 60),
            ],
            duration: 120
        )!
    }

    func testDistanceOneDegreeLatitude() {
        let d = Geo.distance(Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 1, longitude: 0))
        XCTAssertEqual(d, 111_195, accuracy: 100)
    }

    func testProgressAndUpcomingManeuver() {
        let engine = NavigationEngine(route: makeRoute())
        let s = engine.update(location: Coordinate(latitude: 40.0075, longitude: -100))
        XCTAssertEqual(s.status, .onRoute)
        XCTAssertEqual(s.nextManeuver, .turnRight)
        XCTAssertEqual(s.distanceToManeuver, 0.0025 * 111_195, accuracy: 15)
    }

    func testOffRouteNeedsRepeatedStrikes() {
        // About 60 m east of the road: past the 35 m threshold but not 3x it, so 3 consecutive fixes are needed.
        let near = NavigationEngine(route: makeRoute())
        let slightlyAway = Coordinate(latitude: 40.003, longitude: -99.9993)
        XCTAssertEqual(near.update(location: slightlyAway).status, .onRoute)
        XCTAssertEqual(near.update(location: slightlyAway).status, .onRoute)
        XCTAssertEqual(near.update(location: slightlyAway).status, .offRoute)

        // Hundreds of meters away confirms after 2 fixes.
        let far = NavigationEngine(route: makeRoute())
        let wayAway = Coordinate(latitude: 40.003, longitude: -99.99)
        XCTAssertEqual(far.update(location: wayAway).status, .onRoute)
        XCTAssertEqual(far.update(location: wayAway).status, .offRoute)
    }

    func testArrival() {
        let route = makeRoute()
        let engine = NavigationEngine(route: route)
        XCTAssertEqual(engine.update(location: route.polyline.last!).status, .arrived)
    }

    func testAnnouncerFiresEachStageOnce() {
        let route = makeRoute()
        let engine = NavigationEngine(route: route)
        let announcer = Announcer()
        var spoken: [Announcement.Stage] = []
        for i in 0...10 {
            let s = engine.update(location: Coordinate(latitude: 40 + Double(i) * 0.001, longitude: -100))
            if let a = announcer.next(for: s, speed: 10) { spoken.append(a.stage) }
            _ = announcer.next(for: s, speed: 10)
        }
        XCTAssertEqual(spoken, [.far, .near])
    }

    func testTurnClassification() {
        let north = Geo.bearing(from: Coordinate(latitude: 0, longitude: 0), to: Coordinate(latitude: 1, longitude: 0))
        let east = Geo.bearing(from: Coordinate(latitude: 0, longitude: 0), to: Coordinate(latitude: 0, longitude: 1))
        XCTAssertEqual(north, 0, accuracy: 1e-6)
        XCTAssertEqual(east, 90, accuracy: 1e-6)
        XCTAssertEqual(Maneuver.classify(turnAngle: Geo.turnAngle(before: north, after: east)), .turnRight)
        XCTAssertEqual(Maneuver.classify(turnAngle: Geo.turnAngle(before: 355, after: 5)), .straight)
        XCTAssertEqual(Maneuver.classify(turnAngle: Geo.turnAngle(before: 10, after: 330)), .turnSlightLeft)
        XCTAssertEqual(Maneuver.classify(turnAngle: Geo.turnAngle(before: 0, after: 180)), .uturnRight)
        XCTAssertEqual(Maneuver.fromInstruction("Enter the roundabout", fallback: .turnRight), .roundaboutRight)
    }

    func testCoursePrefersSegmentYouAreTravelling() {
        // Out-and-back on (almost) the same road: heading disambiguates which leg you're on.
        let a = Coordinate(latitude: 40, longitude: -100)
        let b = Coordinate(latitude: 40.01, longitude: -100)
        let c = Coordinate(latitude: 40.01, longitude: -99.99995)   // ~4 m east
        let d = Coordinate(latitude: 40, longitude: -99.99995)
        let route = Route(polyline: [a, b, c, d], steps: [], duration: 100)!
        let engine = NavigationEngine(route: route)
        let s = engine.update(location: Coordinate(latitude: 40.004, longitude: -99.999975), course: 180, speed: 12)
        XCTAssertEqual(s.segment, 2)
    }

    func testDeadReckoningAdvancesAndIsMarkedEstimated() {
        let engine = NavigationEngine(route: makeRoute())
        let fix = engine.update(location: Coordinate(latitude: 40.002, longitude: -100))
        let est = engine.extrapolate(speed: 20, since: 5)
        XCTAssertTrue(est.isEstimated)
        XCTAssertEqual(est.progress - fix.progress, 100, accuracy: 0.001)
        XCTAssertEqual(est.status, .onRoute)
        // A later real fix still matches correctly.
        let again = engine.update(location: Coordinate(latitude: 40.003, longitude: -100))
        XCTAssertFalse(again.isEstimated)
        XCTAssertEqual(again.progress, fix.progress + 0.001 * 111_195, accuracy: 15)
    }

    func testThenChainingForCloseManeuvers() {
        let pts = (0...6).map { Coordinate(latitude: 40 + Double($0) * 0.001, longitude: -100) }
        let len = Route(polyline: pts, steps: [], duration: 0)!.distance
        let route = Route(polyline: pts, steps: [
            RouteStep(instruction: "Head north", maneuver: .straight, distance: len * 0.5, duration: 30),
            RouteStep(instruction: "Turn left", maneuver: .turnLeft, distance: 100, duration: 10),
            RouteStep(instruction: "Turn right", maneuver: .turnRight, distance: len * 0.5 - 100, duration: 30),
        ], duration: 70)!
        let s = NavigationEngine(route: route).update(location: pts[0])
        XCTAssertEqual(s.thenInstruction, "Turn right")
        XCTAssertEqual(Announcer().next(for: s, speed: 10)?.then, "Turn right")
    }

    func testLaneGuidanceFromOverpassJSON() {
        // Northbound one-way road with a left-turn lane, two through lanes and a right-turn lane.
        let json = """
        {"elements":[{"type":"way","tags":{"highway":"primary","oneway":"yes","lanes":"4","turn:lanes":"left|through|through|right"},
         "geometry":[{"lat":40.0,"lon":-100.0},{"lat":40.001,"lon":-100.0}]}]}
        """
        let point = Coordinate(latitude: 40.0005, longitude: -100.0)
        let right = OSMLanes.guidance(from: Data(json.utf8), at: point, travelBearing: 0, maneuver: .turnRight)
        XCTAssertEqual(right?.lanes.count, 4)
        XCTAssertEqual(right?.recommendedPositions, [3])
        let straight = OSMLanes.guidance(from: Data(json.utf8), at: point, travelBearing: 0, maneuver: .straight)
        XCTAssertEqual(straight?.recommendedPositions, [1, 2])
        // Driving the wrong way along a one-way road yields nothing.
        XCTAssertNil(OSMLanes.guidance(from: Data(json.utf8), at: point, travelBearing: 180, maneuver: .turnRight))
    }

    func testLaneGuidanceNeedsExplicitMarkingsAndSkipsRoundabouts() {
        XCTAssertNil(OSMLanes.guidance(fromTag: "|", maneuver: .turnLeft))
        XCTAssertNil(OSMLanes.guidance(fromTag: "left|through", maneuver: .roundaboutRight))
        XCTAssertEqual(OSMLanes.guidance(fromTag: "left;through|through;right", maneuver: .turnLeft)?.recommendedPositions, [0])
    }

    func testRoutePositionAtOffset() {
        let route = makeRoute()
        let p = route.position(atOffset: 0.0025 * 111_195)
        XCTAssertEqual(p.coordinate.latitude, 40.0025, accuracy: 1e-4)
        XCTAssertEqual(p.bearing, 0, accuracy: 1e-6)
    }

    func testRoadInfoNameRefAndSpeedLimit() {
        let json = """
        {"elements":[
          {"type":"way","tags":{"highway":"footway","name":"Park Path"},"geometry":[{"lat":40.0,"lon":-100.0},{"lat":40.001,"lon":-100.0}]},
          {"type":"way","tags":{"highway":"primary","name":"Elm Street","ref":"US 1;SR 5","maxspeed":"35 mph","oneway":"yes"},
           "geometry":[{"lat":40.0,"lon":-100.0},{"lat":40.001,"lon":-100.0}]}]}
        """
        let info = OSMRoad.info(from: Data(json.utf8), at: Coordinate(latitude: 40.0005, longitude: -100.0), travelBearing: 0)
        XCTAssertEqual(info?.name, "Elm Street")
        XCTAssertEqual(info?.ref, "US 1")
        XCTAssertEqual(info?.title, "Elm Street")
        XCTAssertEqual(info?.speedLimitKph ?? 0, 56.327, accuracy: 0.01)
        XCTAssertEqual(info?.isHighway, false)
    }

    func testSpeedParsing() {
        XCTAssertEqual(OSMRoad.parseSpeed("50"), 50)
        XCTAssertEqual(OSMRoad.parseSpeed("30 mph") ?? 0, 48.28, accuracy: 0.01)
        XCTAssertNil(OSMRoad.parseSpeed("none"))
        XCTAssertNil(OSMRoad.parseSpeed(nil))
    }

    func testNearestPointAlongRouteAndJoin() {
        let route = makeRoute()
        let r = route.nearest(to: Coordinate(latitude: 40.005, longitude: -99.9995), after: 0)
        XCTAssertEqual(r.along, 0.005 * 111_195, accuracy: 10)
        XCTAssertEqual(r.offset, 0.0005 * 111_195 * cos(40 * .pi / 180), accuracy: 3)
        // Segments wholly behind `after` are not considered: the search starts at the segment containing it.
        XCTAssertEqual(route.nearest(to: Coordinate(latitude: 40.0, longitude: -100), after: 500).along, 0.004 * 111_195, accuracy: 5)

        let a = Route(polyline: [Coordinate(latitude: 40, longitude: -100), Coordinate(latitude: 40.001, longitude: -100)], steps: [], duration: 10)!
        let b = Route(polyline: [Coordinate(latitude: 40.001, longitude: -100), Coordinate(latitude: 40.002, longitude: -100)], steps: [], duration: 20)!
        let joined = Route.joined(a, b)
        XCTAssertEqual(joined?.route.polyline.count, 3)
        XCTAssertEqual(joined?.route.duration, 30)
        XCTAssertEqual(joined?.joinOffset ?? 0, a.distance, accuracy: 1e-6)
    }
}

