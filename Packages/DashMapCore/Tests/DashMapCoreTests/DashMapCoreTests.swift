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

    func testTurnClassification() {
        let north = Geo.bearing(from: Coordinate(latitude: 0, longitude: 0), to: Coordinate(latitude: 1, longitude: 0))
        let east = Geo.bearing(from: Coordinate(latitude: 0, longitude: 0), to: Coordinate(latitude: 0, longitude: 1))
        XCTAssertEqual(north, 0, accuracy: 1e-6)
        XCTAssertEqual(east, 90, accuracy: 1e-6)
        XCTAssertEqual(Maneuver.classify(turnAngle: Geo.turnAngle(before: north, after: east)), .turnRight)
        XCTAssertEqual(Maneuver.classify(turnAngle: Geo.turnAngle(before: 350, after: 10)), .straight)
        XCTAssertEqual(Maneuver.classify(turnAngle: Geo.turnAngle(before: 10, after: 330)), .turnSlightLeft)
        XCTAssertEqual(Maneuver.classify(turnAngle: Geo.turnAngle(before: 0, after: 180)), .uturnRight)
        XCTAssertEqual(Maneuver.fromInstruction("Enter the roundabout", fallback: .turnRight), .roundaboutRight)
    }
}
