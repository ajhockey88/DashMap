import MapKit
import DashMapCore

/// Turns an Apple Maps (MKDirections) route into a DashMapCore `Route`.
/// MapKit steps carry no maneuver type, so it is inferred from the heading change between steps.
enum MapKitRouter {
    /// Returns the quickest route (by Apple's traffic-aware travel time) first, followed by any alternatives Apple Maps offers.
    static func routes(from origin: Coordinate, to destination: MKMapItem) async throws -> [Route] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)))
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = true
        request.departureDate = Date()   // ask for the time with today's traffic, not a typical-day estimate

        let response = try await MKDirections(request: request).calculate()
        // Apple lists its preferred route first, which is not always the quickest with traffic; put the shortest time first.
        let routes = response.routes
            .sorted { $0.expectedTravelTime < $1.expectedTravelTime }
            .compactMap { convert($0, destination: destination.placemark.coordinate) }
        guard !routes.isEmpty else { throw RouterError.noRoute }
        return routes
    }

    enum RouterError: LocalizedError {
        case noRoute
        var errorDescription: String? { "No driving route found." }
    }

    static func convert(_ mk: MKRoute, destination: CLLocationCoordinate2D? = nil) -> Route? {
        let polyline = coordinates(of: mk.polyline)
        var steps: [RouteStep] = []
        var previousHeading: Double?
        let appleSteps = mk.steps.map { "\(Int($0.distance)) m · \($0.instructions.isEmpty ? "(no text)" : $0.instructions)" }

        for step in mk.steps {
            let pts = coordinates(of: step.polyline)
            let heading = pts.count >= 2 ? Geo.bearing(from: pts[0], to: farPoint(in: pts)) : nil

            var maneuver = Maneuver.straight
            if let before = previousHeading, let after = heading {
                maneuver = .classify(turnAngle: Geo.turnAngle(before: before, after: after))
            }
            maneuver = .fromInstruction(step.instructions, fallback: maneuver)

            // The first MapKit step is usually an empty "depart" step.
            if step.instructions.isEmpty && step.distance == 0 { continue }
            steps.append(RouteStep(
                instruction: step.instructions.isEmpty ? "Continue" : step.instructions,
                maneuver: maneuver,
                distance: step.distance,
                duration: 0
            ))
            if let heading = pts.count >= 2 ? Geo.bearing(from: nearEnd(of: pts), to: pts[pts.count - 1]) : heading {
                previousHeading = heading
            }
        }

        // MapKit gives only a route-wide time; spread it by distance.
        let total = steps.reduce(0) { $0 + $1.distance }
        for i in steps.indices where total > 0 {
            steps[i].duration = mk.expectedTravelTime * steps[i].distance / total
        }
        // Apple's "destination is on the left/right" can be on the wrong side; check it against where the destination really is.
        if let destination, polyline.count >= 2, let last = steps.indices.last, steps[last].maneuver == .arrive {
            let end = polyline[polyline.count - 1]
            steps[last].instruction = Route.correctedArrival(
                steps[last].instruction, routeEnd: end,
                travelBearing: Geo.bearing(from: polyline[polyline.count - 2], to: end),
                destination: Coordinate(latitude: destination.latitude, longitude: destination.longitude)
            )
        }
        var route = Route(polyline: polyline, steps: steps, duration: mk.expectedTravelTime)
        route?.appleSteps = appleSteps
        return route
    }

    private static func coordinates(of line: MKPolyline) -> [Coordinate] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: line.pointCount)
        line.getCoordinates(&coords, range: NSRange(location: 0, length: line.pointCount))
        return coords.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// First vertex at least 10 m from the start (or the last vertex), so a tiny first segment doesn't skew the heading.
    private static func farPoint(in pts: [Coordinate]) -> Coordinate {
        pts.dropFirst().first { Geo.distance(pts[0], $0) >= 10 } ?? pts[pts.count - 1]
    }

    private static func nearEnd(of pts: [Coordinate]) -> Coordinate {
        let end = pts[pts.count - 1]
        return pts.dropLast().last { Geo.distance($0, end) >= 10 } ?? pts[0]
    }
}
