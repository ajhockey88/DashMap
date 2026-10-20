import Foundation

/// Picks the OpenStreetMap way you're driving on from an Overpass `out tags geom` response.
enum OSMWays {
    struct Match {
        var offset: Double
        /// True when your direction of travel follows the way's drawn direction.
        var alongWay: Bool
        var isOneway: Bool
        var tags: [String: String]
    }

    static func nearest(
        in data: Data,
        at point: Coordinate,
        travelBearing: Double,
        maxOffset: Double = 20,
        accepting: (_ tags: [String: String], _ alongWay: Bool, _ isOneway: Bool) -> Bool
    ) -> Match? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }

        var best: Match?
        for element in response.elements where element.type == "way" {
            guard let tags = element.tags, let geometry = element.geometry, geometry.count >= 2 else { continue }
            let pts = geometry.map { Coordinate(latitude: $0.lat, longitude: $0.lon) }

            var nearest = (offset: Double.infinity, bearing: 0.0)
            for i in 0..<(pts.count - 1) {
                let r = Geo.project(point, onto: pts[i], pts[i + 1])
                if r.offset < nearest.offset { nearest = (r.offset, Geo.bearing(from: pts[i], to: pts[i + 1])) }
            }
            guard nearest.offset <= maxOffset else { continue }

            let alongWay = abs(Geo.turnAngle(before: travelBearing, after: nearest.bearing)) < 90
            let oneway = tags["oneway"]
            let forwardOnly = oneway == "yes" || oneway == "true" || oneway == "1"
            let reverseOnly = oneway == "-1"
            if (forwardOnly && !alongWay) || (reverseOnly && alongWay) { continue }
            let isOneway = forwardOnly || reverseOnly
            guard accepting(tags, alongWay, isOneway) else { continue }

            if nearest.offset < (best?.offset ?? .infinity) {
                best = Match(offset: nearest.offset, alongWay: alongWay, isOneway: isOneway, tags: tags)
            }
        }
        return best
    }

    private struct Response: Decodable { var elements: [Element] }
    private struct Element: Decodable {
        var type: String
        var tags: [String: String]?
        var geometry: [Point]?
    }
    private struct Point: Decodable { var lat: Double; var lon: Double }
}
