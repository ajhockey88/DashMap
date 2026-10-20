import Foundation

/// Highway exit details for an upcoming ramp: "Exit 24 toward Springfield, Boston".
public struct ExitInfo: Equatable, Sendable {
    public var number: String?
    public var toward: String?

    public var summary: String? {
        switch (number, toward) {
        case let (n?, t?): return "Exit \(n) toward \(t)"
        case let (n?, nil): return "Exit \(n)"
        case let (nil, t?): return "Toward \(t)"
        default: return nil
        }
    }
}

public enum OSMExit {
    /// Looks for a motorway junction (exit number) and the ramp's signed destinations near `point`.
    public static func info(in corridor: Corridor, at point: Coordinate) -> ExitInfo? {
        let junction = corridor.nodes
            .filter { $0.tags["highway"] == "motorway_junction" }
            .map { (node: $0, d: Geo.distance(point, $0.coordinate)) }
            .filter { $0.d <= 150 }
            .min { $0.d < $1.d }?.node

        let ramp = corridor.ways
            .filter { ($0.tags["highway"] ?? "").hasSuffix("_link") }
            .map { (way: $0, d: $0.points.map { Geo.distance(point, $0) }.min() ?? .infinity) }
            .filter { $0.d <= 80 }
            .min { $0.d < $1.d }?.way

        let number = junction?.tags["ref"] ?? junction?.tags["junction:ref"]
        let signed = ramp?.tags["destination"] ?? ramp?.tags["destination:forward"]
            ?? ramp?.tags["destination:ref"] ?? junction?.tags["exit_to"] ?? junction?.tags["name"] ?? ramp?.tags["exit_to"]
        let toward = signed.map { $0.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.prefix(3).joined(separator: ", ") }
        let info = ExitInfo(number: number, toward: (toward?.isEmpty ?? true) ? nil : toward)
        return info.summary == nil ? nil : info
    }
}

/// Corrects MapKit's heading-based turn guess using the kind of road you leave and join.
public enum OSMManeuver {
    public typealias Spot = (point: Coordinate, bearing: Double)

    /// - Parameters:
    ///   - approach: a spot just before the maneuver and your travel bearing there.
    ///   - departure: a spot just after it and the bearing there.
    public static func refine(_ base: Maneuver, in ways: [CorridorWay], approach: Spot, departure: Spot) -> Maneuver {
        switch base {
        case .roundaboutLeft, .roundaboutRight, .arrive, .ferry, .ferryTrain, .uturnLeft, .uturnRight,
             .turnLeft, .turnRight, .turnSharpLeft, .turnSharpRight:
            return base
        default: break
        }

        let drivable = { (tags: [String: String], _: Bool, _: Bool) in tags["highway"].map(OSMRoad.drivable.contains) ?? false }
        guard let before = OSMWays.nearest(in: ways, at: approach.point, travelBearing: approach.bearing, maxOffset: 20, accepting: drivable),
              let after = OSMWays.nearest(in: ways, at: departure.point, travelBearing: departure.bearing, maxOffset: 20, accepting: drivable),
              before.way.id != after.way.id || before.way.id == nil else { return base }

        let from = before.tags["highway"] ?? ""
        let to = after.tags["highway"] ?? ""
        let angle = Geo.turnAngle(before: approach.bearing, after: departure.bearing)
        let isFast = { (h: String) in h.hasPrefix("motorway") || h.hasPrefix("trunk") }

        // Leaving a fast road onto a ramp.
        if !from.hasSuffix("_link"), to.hasSuffix("_link"), isFast(from) {
            return angle < -3 ? .rampLeft : .rampRight   // right-hand exits are the default when the geometry is straight
        }
        // Joining a road from a ramp without a real turn.
        if from.hasSuffix("_link"), !to.hasSuffix("_link"), abs(angle) < 45 {
            return .merge
        }
        return base
    }
}
