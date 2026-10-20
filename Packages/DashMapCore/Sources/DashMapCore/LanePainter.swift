import Foundation

/// A filled shape on the road surface. `isActive` marks lanes you should use.
public struct LanePolygon: Sendable {
    public var points: [Coordinate]
    public var isActive: Bool
}

/// Lane graphics for the approach to a turn, as real-world shapes that sit on the road: a ribbon along each lane
/// you should use, and arrows painted in every lane (white for usable lanes, gray for the rest).
public struct LanePaint: Sendable {
    public var ribbons: [[Coordinate]]
    public var arrows: [LanePolygon]
}

public enum LanePainter {
    public static let laneWidth = 3.4

    /// - Parameters:
    ///   - maneuverOffset: where along the route the maneuver happens (meters).
    ///   - approach: how far before the maneuver the ribbon starts.
    public static func paint(
        route: Route,
        maneuverOffset: Double,
        guidance: LaneGuidance,
        laneWidth w: Double = laneWidth,
        approach: Double = 160
    ) -> LanePaint? {
        let count = guidance.lanes.count
        guard count >= 2, !guidance.recommendedPositions.isEmpty, maneuverOffset > 8 else { return nil }

        let end = min(maneuverOffset, route.distance) - 4
        let start = max(0, end - approach)
        guard end - start >= 8 else { return nil }

        var samples: [Double] = []
        var d = start
        while d < end { samples.append(d); d += 4 }
        samples.append(end)
        let frames = samples.map { route.position(atOffset: $0) }

        var ribbons: [[Coordinate]] = []
        for lane in guidance.recommendedPositions {
            let c = lateral(lane: lane, count: count, oneway: guidance.isOneway, width: w)
            let left = frames.map { offset($0.coordinate, bearing: $0.bearing, right: c - w * 0.45, forward: 0) }
            let right = frames.map { offset($0.coordinate, bearing: $0.bearing, right: c + w * 0.45, forward: 0) }
            ribbons.append(left + right.reversed())
        }

        var arrows: [LanePolygon] = []
        for distanceBefore in [30.0, 62.0] where maneuverOffset - distanceBefore > 0 {
            let frame = route.position(atOffset: maneuverOffset - distanceBefore)
            for (i, lane) in guidance.lanes.enumerated() {
                let c = lateral(lane: i, count: count, oneway: guidance.isOneway, width: w)
                for shape in arrowShapes(lane.indications) {
                    let pts = shape.map { offset(frame.coordinate, bearing: frame.bearing, right: c + $0.x, forward: $0.y) }
                    arrows.append(LanePolygon(points: pts, isActive: lane.isRecommended))
                }
            }
        }
        return LanePaint(ribbons: ribbons, arrows: arrows)
    }

    /// Meters right of the road's centerline for the middle of lane `i` (0 is the leftmost).
    static func lateral(lane i: Int, count n: Int, oneway: Bool, width w: Double) -> Double {
        oneway ? (Double(i) - Double(n - 1) / 2) * w : (Double(i) + 0.5) * w
    }

    /// `right` and `forward` are meters relative to `c`, facing `bearing`.
    static func offset(_ c: Coordinate, bearing: Double, right: Double, forward: Double) -> Coordinate {
        let b = bearing * .pi / 180
        let east = right * cos(b) + forward * sin(b)
        let north = -right * sin(b) + forward * cos(b)
        let lat = c.latitude + north / 111_320
        let lon = c.longitude + east / (111_320 * max(0.1, cos(c.latitude * .pi / 180)))
        return Coordinate(latitude: lat, longitude: lon)
    }

    typealias Point = (x: Double, y: Double)

    /// Painted arrow for a lane as a few filled polygons in lane-local meters (x right, y forward):
    /// a stem plus an arm and arrowhead for every allowed direction.
    static func arrowShapes(_ indications: [LaneIndication]) -> [[Point]] {
        let marked = indications.filter { $0 != .none }
        let branches = marked.isEmpty ? [LaneIndication.through] : marked
        let hasTurn = branches.contains { $0 != .through }
        let stemTop = hasTurn ? 2.4 : 3.6

        var shapes: [[Point]] = [[(-0.25, 0), (0.25, 0), (0.25, stemTop), (-0.25, stemTop)]]
        for branch in branches {
            let degrees: Double
            switch branch {
            case .through, .none: degrees = 0
            case .slightLeft: degrees = -40
            case .left, .mergeToLeft: degrees = -90
            case .sharpLeft: degrees = -130
            case .slightRight: degrees = 40
            case .right, .mergeToRight: degrees = 90
            case .sharpRight: degrees = 130
            case .reverse: degrees = -150
            }
            let a = degrees * .pi / 180
            let dir: Point = (sin(a), cos(a))
            let perp: Point = (cos(a), -sin(a))
            let from: Point = (0, stemTop)
            let armLength = branch == .through ? 1.2 : 2.0
            let to: Point = (from.x + dir.x * armLength, from.y + dir.y * armLength)

            // Arm.
            shapes.append([
                (from.x - perp.x * 0.25, from.y - perp.y * 0.25), (from.x + perp.x * 0.25, from.y + perp.y * 0.25),
                (to.x + perp.x * 0.25, to.y + perp.y * 0.25), (to.x - perp.x * 0.25, to.y - perp.y * 0.25),
            ])
            // Arrowhead.
            shapes.append([
                (to.x - perp.x * 0.85, to.y - perp.y * 0.85), (to.x + perp.x * 0.85, to.y + perp.y * 0.85),
                (to.x + dir.x * 1.3, to.y + dir.y * 1.3),
            ])
        }
        return shapes
    }
}
