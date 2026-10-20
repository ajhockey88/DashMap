import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum LaneIndication: String, Sendable {
    case sharpLeft = "sharp_left"
    case left
    case slightLeft = "slight_left"
    case through
    case slightRight = "slight_right"
    case right
    case sharpRight = "sharp_right"
    case reverse
    case mergeToLeft = "merge_to_left"
    case mergeToRight = "merge_to_right"
    /// No marking, or an unrecognized value.
    case none
}

public struct Lane: Equatable, Sendable {
    public var indications: [LaneIndication]
    /// True when this lane can be used for the upcoming maneuver.
    public var isRecommended: Bool
}

/// Lanes on the approach to the next maneuver, left to right in the direction of travel.
public struct LaneGuidance: Equatable, Sendable {
    public var lanes: [Lane]
    public var recommendedPositions: [Int] { lanes.indices.filter { lanes[$0].isRecommended } }
}

/// Lane guidance from OpenStreetMap `turn:lanes` tags (fetched with an Overpass query). Coverage depends on
/// local mapping; when a road has no lane tags the result is nil and nothing is shown.
public enum OSMLanes {
    /// Overpass QL for ways within 20 m of `point` that carry lane-turn tags.
    public static func query(near point: Coordinate) -> String {
        let at = String(format: "%.6f,%.6f", point.latitude, point.longitude)
        return "[out:json][timeout:8];way(around:20,\(at))[highway][~\"^turn:lanes\"~\".\"];out tags geom;"
    }

    /// - Parameters:
    ///   - point: a spot on the route shortly before the maneuver, used to pick the road you're on.
    ///   - travelBearing: your direction of travel there, used to pick forward/backward lanes.
    public static func guidance(from data: Data, at point: Coordinate, travelBearing: Double, maneuver: Maneuver) -> LaneGuidance? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }

        var best: (offset: Double, value: String)?
        for element in response.elements where element.type == "way" {
            guard let tags = element.tags, let geometry = element.geometry, geometry.count >= 2 else { continue }
            let pts = geometry.map { Coordinate(latitude: $0.lat, longitude: $0.lon) }

            var nearest = (offset: Double.infinity, bearing: 0.0)
            for i in 0..<(pts.count - 1) {
                let r = Geo.project(point, onto: pts[i], pts[i + 1])
                if r.offset < nearest.offset { nearest = (r.offset, Geo.bearing(from: pts[i], to: pts[i + 1])) }
            }
            guard nearest.offset <= 20 else { continue }

            let alongWay = abs(Geo.turnAngle(before: travelBearing, after: nearest.bearing)) < 90
            let oneway = tags["oneway"]
            let isOneway = oneway == "yes" || oneway == "true" || oneway == "1" || oneway == "-1"
            if (oneway == "yes" || oneway == "true" || oneway == "1") && !alongWay { continue }
            if oneway == "-1" && alongWay { continue }

            // Tags are listed left to right in the direction the lanes travel.
            let value = (isOneway ? tags["turn:lanes"] : nil) ?? tags[alongWay ? "turn:lanes:forward" : "turn:lanes:backward"]
            if let value, nearest.offset < (best?.offset ?? .infinity) { best = (nearest.offset, value) }
        }
        guard let value = best?.value else { return nil }
        return guidance(fromTag: value, maneuver: maneuver)
    }

    static func guidance(fromTag value: String, maneuver: Maneuver) -> LaneGuidance? {
        let lanes: [[LaneIndication]] = value.split(separator: "|", omittingEmptySubsequences: false).map { lane in
            lane.split(separator: ";").map { LaneIndication(rawValue: String($0)) ?? .none }
        }
        guard lanes.count >= 2,
              lanes.contains(where: { $0.contains { $0 != .none } }),
              let accepted = acceptedIndications(for: maneuver) else { return nil }

        let result = lanes.map { indications -> Lane in
            let list = indications.isEmpty ? [LaneIndication.none] : indications
            return Lane(indications: list, isRecommended: list.contains { accepted.contains($0) })
        }
        let guidance = LaneGuidance(lanes: result)
        return guidance.recommendedPositions.isEmpty ? nil : guidance
    }

    /// Which lane markings serve a maneuver; nil where lane guidance doesn't apply (roundabouts, arrival).
    static func acceptedIndications(for maneuver: Maneuver) -> Set<LaneIndication>? {
        switch maneuver {
        case .turnLeft, .rampLeft, .forkLeft: return [.left, .slightLeft, .sharpLeft]
        case .turnSlightLeft: return [.slightLeft, .left]
        case .turnSharpLeft: return [.sharpLeft, .left]
        case .uturnLeft: return [.reverse, .left]
        case .turnRight, .rampRight, .forkRight: return [.right, .slightRight, .sharpRight]
        case .turnSlightRight: return [.slightRight, .right]
        case .turnSharpRight: return [.sharpRight, .right]
        case .uturnRight: return [.reverse, .right]
        case .straight, .merge, .unspecified: return [.through, .none]
        case .roundaboutLeft, .roundaboutRight, .ferry, .ferryTrain, .arrive: return nil
        }
    }

    private struct Response: Decodable { var elements: [Element] }
    private struct Element: Decodable {
        var type: String
        var tags: [String: String]?
        var geometry: [Point]?
    }
    private struct Point: Decodable { var lat: Double; var lon: Double }
}

extension Route {
    /// The route position (and travel bearing) `offset` meters from the start.
    public func position(atOffset offset: Double) -> (coordinate: Coordinate, bearing: Double) {
        let d = min(max(offset, 0), distance)
        var lo = 0, hi = cumulative.count - 2
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cumulative[mid] <= d { lo = mid } else { hi = mid - 1 }
        }
        let length = cumulative[lo + 1] - cumulative[lo]
        let t = length > 0 ? (d - cumulative[lo]) / length : 0
        let a = polyline[lo], b = polyline[lo + 1]
        return (
            Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t),
            segmentBearings[lo]
        )
    }
}
