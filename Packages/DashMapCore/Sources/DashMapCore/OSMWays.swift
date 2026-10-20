import Foundation

/// Picks the OpenStreetMap way you're driving on from a set of nearby ways.
enum OSMWays {
    struct Match {
        var way: CorridorWay
        var offset: Double
        /// True when your direction of travel follows the way's drawn direction.
        var alongWay: Bool
        var isOneway: Bool
        var tags: [String: String] { way.tags }
    }

    static func nearest(
        in data: Data,
        at point: Coordinate,
        travelBearing: Double,
        maxOffset: Double = 20,
        accepting: (_ tags: [String: String], _ alongWay: Bool, _ isOneway: Bool) -> Bool
    ) -> Match? {
        guard let corridor = OSMCorridor.parse(data) else { return nil }
        return nearest(in: corridor.ways, at: point, travelBearing: travelBearing, maxOffset: maxOffset, accepting: accepting)
    }

    static func nearest(
        in ways: [CorridorWay],
        at point: Coordinate,
        travelBearing: Double,
        maxOffset: Double = 20,
        accepting: (_ tags: [String: String], _ alongWay: Bool, _ isOneway: Bool) -> Bool
    ) -> Match? {
        var best: Match?
        for way in ways where !way.isFar(from: point, meters: maxOffset) {
            let pts = way.points
            var nearest = (offset: Double.infinity, bearing: 0.0)
            for i in 0..<(pts.count - 1) {
                let r = Geo.project(point, onto: pts[i], pts[i + 1])
                if r.offset < nearest.offset { nearest = (r.offset, Geo.bearing(from: pts[i], to: pts[i + 1])) }
            }
            guard nearest.offset <= maxOffset else { continue }

            let alongWay = abs(Geo.turnAngle(before: travelBearing, after: nearest.bearing)) < 90
            let oneway = way.tags["oneway"]
            let forwardOnly = oneway == "yes" || oneway == "true" || oneway == "1"
            let reverseOnly = oneway == "-1"
            if (forwardOnly && !alongWay) || (reverseOnly && alongWay) { continue }
            let isOneway = forwardOnly || reverseOnly
            guard accepting(way.tags, alongWay, isOneway) else { continue }

            if nearest.offset < (best?.offset ?? .infinity) {
                best = Match(way: way, offset: nearest.offset, alongWay: alongWay, isOneway: isOneway)
            }
        }
        return best
    }
}
