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

    func testTurnStaysCurrentUntilTheCarIsPastIt() {
        let route = makeRoute()
        let turnAt = route.steps[1].startOffset
        let engine = NavigationEngine(route: route)
        let atTurn = engine.update(location: route.position(atOffset: turnAt + 5).coordinate)
        XCTAssertEqual(atTurn.nextManeuver, .turnRight, "still turning: the next instruction must not appear yet")
        XCTAssertEqual(atTurn.distanceToManeuver, 0, accuracy: 0.001)
        let past = engine.update(location: route.position(atOffset: turnAt + 60).coordinate)
        XCTAssertEqual(past.stepIndex, 1)
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

    func testCorridorParseMergeAndQuery() {
        let json = """
        {"elements":[
          {"type":"way","id":1,"tags":{"highway":"primary","name":"Elm Street"},"geometry":[{"lat":40.0,"lon":-100.0},{"lat":40.001,"lon":-100.0}]},
          {"type":"node","id":9,"lat":40.0005,"lon":-100.0001,"tags":{"highway":"motorway_junction","ref":"24"}}]}
        """
        var corridor = OSMCorridor.parse(Data(json.utf8))!
        XCTAssertEqual(corridor.ways.count, 1)
        XCTAssertEqual(corridor.nodes.first?.tags["ref"], "24")
        corridor.merge(OSMCorridor.parse(Data(json.utf8))!)
        XCTAssertEqual(corridor.ways.count, 1, "the same way must not be added twice")

        let q = OSMCorridor.query(for: makeRoute(), from: 0, to: 500, spacing: 100)
        XCTAssertTrue(q.contains("way[highway][highway!~"), "roads are fetched by bounding box")
        XCTAssertTrue(q.contains("motorway_junction"))
        XCTAssertFalse(q.contains("around"), "an around search over a long polyline times out on public servers")
    }

    func testTurnDirectionFollowsTheRouteGeometry() {
        // Northbound for 1.1 km, then west (a left turn), but the step claims a right turn.
        var pts = (0...10).map { Coordinate(latitude: 40 + Double($0) * 0.001, longitude: -100) }
        pts += (1...10).map { Coordinate(latitude: 40.010, longitude: -100 - Double($0) * 0.001 * 1.3) }
        let first = Geo.distance(pts[0], pts[10])
        let len = Route(polyline: pts, steps: [], duration: 0)!.distance
        let route = Route(polyline: pts, steps: [
            RouteStep(instruction: "Head north", maneuver: .straight, distance: first, duration: 60),
            RouteStep(instruction: "Turn right onto Elm St", maneuver: .turnRight, distance: len - first, duration: 60),
        ], duration: 120)!
        XCTAssertEqual(route.steps[1].maneuver, .turnLeft)
        XCTAssertEqual(route.steps[1].instruction, "Turn left onto Elm St")
        // A correct label is left alone.
        XCTAssertEqual(makeRoute().steps[1].maneuver, .turnRight)
        XCTAssertEqual(makeRoute().steps[1].instruction, "Turn right onto Elm St")
    }

    func testFirstStepTurnIsReplacedByAHeading() {
        // Heads due south; Apple Maps' "Turn right onto N Glebe Rd" as step one assumes a heading the car may not have.
        let pts = (0...10).map { Coordinate(latitude: 40 - Double($0) * 0.001, longitude: -100) }
        let route = Route(polyline: pts, steps: [
            RouteStep(instruction: "Turn right onto N Glebe Rd", maneuver: .turnRight, distance: 1_100, duration: 60),
        ], duration: 60)!
        XCTAssertEqual(route.steps[0].instruction, "Head south on N Glebe Rd")
        XCTAssertEqual(route.steps[0].maneuver, .straight)
    }

    func testACornerMissingFromTheStepsGetsATurnOfItsOwn() {
        // North for ~550 m, a left turn to the west for ~550 m, then a right turn north again.
        var pts = (0...5).map { Coordinate(latitude: 40 + Double($0) * 0.001, longitude: -100) }
        pts += (1...5).map { Coordinate(latitude: 40.005, longitude: -100 - Double($0) * 0.0013) }
        pts += (1...5).map { Coordinate(latitude: 40.005 + Double($0) * 0.001, longitude: -100.0065) }
        let len = Route(polyline: pts, steps: [], duration: 0)!.distance
        // Apple's list knows only about the right turn onto the last leg.
        let rightAt = Geo.distance(pts[0], pts[5]) + Geo.distance(pts[5], pts[10])
        let route = Route(polyline: pts, steps: [
            RouteStep(instruction: "Head north", maneuver: .straight, distance: rightAt, duration: 60),
            RouteStep(instruction: "Turn right onto Elm St", maneuver: .turnRight, distance: len - rightAt, duration: 60),
        ], duration: 120)!
        XCTAssertEqual(route.steps.map(\.instruction), ["Head north", "Turn left", "Turn right onto Elm St"])
        XCTAssertEqual(route.steps[1].maneuver, .turnLeft)
        XCTAssertEqual(route.steps[1].startOffset, Geo.distance(pts[0], pts[5]), accuracy: 15)
        XCTAssertEqual(route.steps[2].startOffset, rightAt, accuracy: 1)
    }

    func testArrivalSideIsCheckedAgainstTheDestinationPoint() {
        let end = Coordinate(latitude: 40, longitude: -100)
        let eastOfEnd = Coordinate(latitude: 40, longitude: -100 + 0.0003)   // ~25 m east; heading north, that is the right side
        XCTAssertEqual(Route.correctedArrival("Your destination is on the left", routeEnd: end, travelBearing: 0, destination: eastOfEnd),
                       "Your destination is on the right")
        XCTAssertEqual(Route.correctedArrival("Your destination is on the right", routeEnd: end, travelBearing: 0, destination: eastOfEnd),
                       "Your destination is on the right")
        XCTAssertEqual(Route.correctedArrival("Your destination is on the left", routeEnd: end, travelBearing: 0, destination: end),
                       "Your destination is on the left", "too close to tell, so leave it")
    }

    func testOverpassRuntimeErrorIsAFailureNotAnEmptyCorridor() {
        let json = #"{"elements":[],"remark":"runtime error: Query timed out in \"query\" at line 1 after 31 seconds."}"#
        XCTAssertNil(OSMCorridor.parse(Data(json.utf8)))
        XCTAssertNotNil(OSMCorridor.parse(Data(#"{"elements":[]}"#.utf8)))
    }

    func testExitInfoFromJunctionAndRamp() {
        let json = """
        {"elements":[
          {"type":"node","id":9,"lat":40.0005,"lon":-100.0001,"tags":{"highway":"motorway_junction","ref":"24"}},
          {"type":"way","id":2,"tags":{"highway":"motorway_link","destination":"Springfield;Boston;Albany;Utica"},
           "geometry":[{"lat":40.0004,"lon":-100.0002},{"lat":40.0010,"lon":-100.0006}]}]}
        """
        let corridor = OSMCorridor.parse(Data(json.utf8))!
        let info = OSMExit.info(in: corridor, at: Coordinate(latitude: 40.0005, longitude: -100.0))
        XCTAssertEqual(info?.number, "24")
        XCTAssertEqual(info?.toward, "Springfield, Boston, Albany")
        XCTAssertEqual(info?.summary, "Exit 24 toward Springfield, Boston, Albany")
        XCTAssertNil(OSMExit.info(in: corridor, at: Coordinate(latitude: 41, longitude: -100)))
    }

    func testRampAndMergeRefinement() {
        let motorway = CorridorWay(id: 1, tags: ["highway": "motorway"], points: [Coordinate(latitude: 40.000, longitude: -100.0), Coordinate(latitude: 40.002, longitude: -100.0)])
        let ramp = CorridorWay(id: 2, tags: ["highway": "motorway_link"], points: [Coordinate(latitude: 40.0021, longitude: -100.0), Coordinate(latitude: 40.003, longitude: -99.999)])
        let approach = (point: Coordinate(latitude: 40.0019, longitude: -100.0), bearing: 0.0)
        let departure = (point: Coordinate(latitude: 40.0022, longitude: -99.9998), bearing: 25.0)
        // Leaving the motorway for a link bending right.
        XCTAssertEqual(OSMManeuver.refine(.turnSlightRight, in: [motorway, ramp], approach: approach, departure: departure), .rampRight)
        // Joining the motorway from the link.
        let joining = OSMManeuver.refine(.straight, in: [motorway, ramp],
                                         approach: (point: Coordinate(latitude: 40.0025, longitude: -99.9995), bearing: 20),
                                         departure: (point: Coordinate(latitude: 40.001, longitude: -100.0), bearing: 0))
        XCTAssertEqual(joining, .merge)
        // Real turns and roundabouts are left alone.
        XCTAssertEqual(OSMManeuver.refine(.turnLeft, in: [motorway, ramp], approach: approach, departure: departure), .turnLeft)
    }

    func testSmootherReducesNoise() {
        var smoother = PositionSmoother()
        let start = Date(timeIntervalSince1970: 1_000_000)
        var rawError = 0.0, smoothError = 0.0
        let metersPerDegree = 111_320.0
        for i in 0..<60 {
            let t = Double(i)
            let truth = Coordinate(latitude: 40 + 15 * t / metersPerDegree, longitude: -100)
            // Deterministic pseudo-noise of up to about 9 m.
            let noiseLat = 9 * sin(t * 1.7) / metersPerDegree
            let noiseLon = 9 * cos(t * 2.3) / (metersPerDegree * cos(40 * .pi / 180))
            let noisy = Coordinate(latitude: truth.latitude + noiseLat, longitude: truth.longitude + noiseLon)
            let out = smoother.update(noisy, accuracy: 8, speed: 15, course: 0, at: start.addingTimeInterval(t))
            if i >= 10 {
                rawError += Geo.distance(noisy, truth)
                smoothError += Geo.distance(out, truth)
            }
        }
        XCTAssertLessThan(smoothError, rawError * 0.7)
    }

    func testSmootherRestartsAfterBigJumpOrGap() {
        var smoother = PositionSmoother()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        _ = smoother.update(Coordinate(latitude: 40, longitude: -100), accuracy: 5, speed: 0, course: nil, at: t0)
        let far = Coordinate(latitude: 40.01, longitude: -100)   // about 1.1 km away
        XCTAssertEqual(smoother.update(far, accuracy: 5, speed: 0, course: nil, at: t0.addingTimeInterval(1)), far)
        let later = Coordinate(latitude: 40.02, longitude: -100)
        XCTAssertEqual(smoother.update(later, accuracy: 5, speed: 0, course: nil, at: t0.addingTimeInterval(60)), later)
    }

    func testLanePaintSitsOnTheRecommendedLane() {
        // One-way road, four lanes, the rightmost is the turn lane: its ribbon is 1.5 lane widths right of center.
        let lanes = [
            Lane(indications: [.left], isRecommended: false),
            Lane(indications: [.through], isRecommended: false),
            Lane(indications: [.through], isRecommended: false),
            Lane(indications: [.right], isRecommended: true),
        ]
        let route = makeRoute()
        let turnAt = Geo.distance(route.polyline[0], route.polyline[10])
        let paint = LanePainter.paint(route: route, maneuverOffset: turnAt, guidance: LaneGuidance(lanes: lanes, isOneway: true))
        XCTAssertEqual(paint?.ribbons.count, 1)

        let ribbon = paint!.ribbons[0]
        let centroid = Coordinate(
            latitude: ribbon.map(\.latitude).reduce(0, +) / Double(ribbon.count),
            longitude: ribbon.map(\.longitude).reduce(0, +) / Double(ribbon.count)
        )
        XCTAssertGreaterThan(centroid.longitude, -100, "right of a northbound route is east")
        XCTAssertEqual(route.nearest(to: centroid).offset, 1.5 * LanePainter.laneWidth, accuracy: 0.4)

        // Arrows are painted in every lane, two rows; only the right lane's are active.
        XCTAssertTrue(paint!.arrows.contains { $0.isActive })
        XCTAssertTrue(paint!.arrows.contains { !$0.isActive })
        XCTAssertNil(LanePainter.paint(route: route, maneuverOffset: 3, guidance: LaneGuidance(lanes: lanes)))
    }

    func testTwoWayLanesSitRightOfCenter() {
        XCTAssertEqual(LanePainter.lateral(lane: 0, count: 2, oneway: false, width: 3.4), 1.7, accuracy: 1e-9)
        XCTAssertEqual(LanePainter.lateral(lane: 1, count: 2, oneway: false, width: 3.4), 5.1, accuracy: 1e-9)
        XCTAssertEqual(LanePainter.lateral(lane: 0, count: 3, oneway: true, width: 3.4), -3.4, accuracy: 1e-9)
    }

    func testTwoTurnLanesAreBothRecommended() {
        // left | through | right | right: a right turn may use either of the last two lanes.
        let both = OSMLanes.guidance(fromTag: "left|through|right|right", maneuver: .turnRight)
        XCTAssertEqual(both?.recommendedPositions, [2, 3])

        // A through-or-right lane also serves a right turn, so three lanes qualify.
        let mixed = OSMLanes.guidance(fromTag: "left|through;right|right|right", maneuver: .turnRight)
        XCTAssertEqual(mixed?.recommendedPositions, [1, 2, 3])

        // Each usable lane gets its own ribbon.
        let route = makeRoute()
        let turnAt = Geo.distance(route.polyline[0], route.polyline[10])
        let paint = LanePainter.paint(route: route, maneuverOffset: turnAt, guidance: both!)
        XCTAssertEqual(paint?.ribbons.count, 2)
        XCTAssertEqual(Set(paint!.arrows.filter(\.isActive).map { $0.points.count }).isEmpty, false)
    }
}

