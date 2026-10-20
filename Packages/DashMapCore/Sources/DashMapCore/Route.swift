import Foundation

public enum Maneuver: String, Sendable {
    case unspecified = "MANEUVER_UNSPECIFIED"
    case turnSlightLeft = "TURN_SLIGHT_LEFT"
    case turnSharpLeft = "TURN_SHARP_LEFT"
    case uturnLeft = "UTURN_LEFT"
    case turnLeft = "TURN_LEFT"
    case turnSlightRight = "TURN_SLIGHT_RIGHT"
    case turnSharpRight = "TURN_SHARP_RIGHT"
    case uturnRight = "UTURN_RIGHT"
    case turnRight = "TURN_RIGHT"
    case straight = "STRAIGHT"
    case rampLeft = "RAMP_LEFT"
    case rampRight = "RAMP_RIGHT"
    case merge = "MERGE"
    case forkLeft = "FORK_LEFT"
    case forkRight = "FORK_RIGHT"
    case ferry = "FERRY"
    case ferryTrain = "FERRY_TRAIN"
    case roundaboutLeft = "ROUNDABOUT_LEFT"
    case roundaboutRight = "ROUNDABOUT_RIGHT"
    /// End of the route.
    case arrive = "ARRIVE"

}

public struct RouteStep: Equatable, Sendable {
    /// What to do at the *start* of this step (MapKit semantics).
    public var instruction: String
    public var maneuver: Maneuver
    public var distance: Double
    public var duration: Double
    /// Meters along the route where this step begins / ends. Filled in by `Route`.
    public internal(set) var startOffset: Double = 0
    public internal(set) var endOffset: Double = 0

    public init(instruction: String, maneuver: Maneuver, distance: Double, duration: Double) {
        self.instruction = instruction
        self.maneuver = maneuver
        self.distance = distance
        self.duration = duration
    }
}

public struct Route: Equatable, Sendable {
    public let polyline: [Coordinate]
    /// Cumulative distance in meters at each polyline vertex.
    public let cumulative: [Double]
    public let steps: [RouteStep]
    public let duration: Double

    public var distance: Double { cumulative[cumulative.count - 1] }

    /// Returns nil when the polyline has fewer than two points.
    public init?(polyline: [Coordinate], steps: [RouteStep], duration: Double) {
        guard polyline.count >= 2 else { return nil }
        var cum = [0.0]
        for i in 1..<polyline.count {
            cum.append(cum[i - 1] + Geo.distance(polyline[i - 1], polyline[i]))
        }
        let length = cum[cum.count - 1]

        var steps = steps
        if steps.isEmpty {
            steps = [RouteStep(instruction: "Continue", maneuver: .straight, distance: length, duration: duration)]
        }
        // Reconcile rounded step lengths/durations with the polyline and the traffic-aware total.
        let distSum = steps.reduce(0) { $0 + $1.distance }
        let durSum = steps.reduce(0) { $0 + $1.duration }
        let dScale = distSum > 0 ? length / distSum : 1
        let tScale = durSum > 0 ? duration / durSum : 1
        var offset = 0.0
        for i in steps.indices {
            steps[i].startOffset = offset
            offset += steps[i].distance * dScale
            steps[i].endOffset = offset
            steps[i].duration *= tScale
        }

        self.polyline = polyline
        self.cumulative = cum
        self.steps = steps
        self.duration = duration
    }
}

extension Maneuver {
    /// Classifies a change of heading. `angle` is in degrees, positive = clockwise (right), in -180...180.
    public static func classify(turnAngle angle: Double) -> Maneuver {
        let magnitude = abs(angle)
        let right = angle > 0
        switch magnitude {
        case ..<20: return .straight
        case ..<45: return right ? .turnSlightRight : .turnSlightLeft
        case ..<135: return right ? .turnRight : .turnLeft
        case ..<170: return right ? .turnSharpRight : .turnSharpLeft
        default: return right ? .uturnRight : .uturnLeft
        }
    }

    /// Keyword overrides for cases geometry can't express, based on the (English) instruction text.
    public static func fromInstruction(_ text: String, fallback: Maneuver) -> Maneuver {
        let t = text.lowercased()
        let isLeft = fallback.rawValue.contains("LEFT")
        if t.contains("roundabout") || t.contains("traffic circle") { return isLeft ? .roundaboutLeft : .roundaboutRight }
        if t.contains("destination") || t.contains("arrive") { return .arrive }
        if t.contains("merge") { return .merge }
        if t.contains("u-turn") { return isLeft ? .uturnLeft : .uturnRight }
        if t.contains("ferry") { return .ferry }
        return fallback
    }
}
