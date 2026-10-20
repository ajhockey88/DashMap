import MapKit
import DashMapCore

/// Turns an Apple Maps (MKDirections) route into a DashMapCore `Route`.
/// MapKit steps carry no maneuver type, so it is inferred from the heading change between steps.
enum MapKitRouter {
    /// Returns the primary route first, followed by any alternatives Apple Maps offers.
    static func routes(from origin: Coordinate, to destination: MKMapItem) async throws -> [Route] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)))
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        let response = try await MKDirections(request: request).calculate()
        let routes = response.routes.compactMap(convert)
        guard !routes.isEmpty else { throw RouterError.noRoute }
        return routes
    }

    enum RouterError: LocalizedError {
        case noRoute
        var errorDescription: String? { "No driving route found." }
    }

    static func convert(_ mk: MKRoute) -> Route? {
        let polyline = coordinates(of: mk.polyline)
        var steps: [RouteStep] = []
        var previousHeading: Double?

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
        return Route(polyline: polyline, steps: steps, duration: mk.expectedTravelTime)
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
