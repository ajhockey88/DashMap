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

    func testPolylineDecodeReferenceExample() {
        let pts = Geo.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(pts.count, 3)
        XCTAssertEqual(pts[0].latitude, 38.5, accuracy: 1e-5)
        XCTAssertEqual(pts[0].longitude, -120.2, accuracy: 1e-5)
        XCTAssertEqual(pts[2].latitude, 43.252, accuracy: 1e-5)
        XCTAssertEqual(pts[2].longitude, -126.453, accuracy: 1e-5)
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
        let engine = NavigationEngine(route: makeRoute())
        let away = Coordinate(latitude: 40.003, longitude: -99.99)
        XCTAssertEqual(engine.update(location: away).status, .onRoute)
        XCTAssertEqual(engine.update(location: away).status, .onRoute)
        XCTAssertEqual(engine.update(location: away).status, .offRoute)
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

    func testParseRoutesResponse() throws {
        let json = """
        {"routes":[{"duration":"120s","polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC"},
         "legs":[{"steps":[
           {"distanceMeters":100,"staticDuration":"10s","navigationInstruction":{"maneuver":"STRAIGHT","instructions":"Head north"}},
           {"distanceMeters":200,"staticDuration":"20s","navigationInstruction":{"maneuver":"SOMETHING_NEW","instructions":"Go"}}]}]}]}
        """
        let route = try RoutesAPI.parse(Data(json.utf8))
        XCTAssertEqual(route.steps.count, 2)
        XCTAssertEqual(route.steps[1].maneuver, .unspecified)
        XCTAssertEqual(route.duration, 120)
        XCTAssertEqual(route.steps.map(\.duration).reduce(0, +), 120, accuracy: 1e-9)
    }
}
