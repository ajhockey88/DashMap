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
    /// Compass bearing of each polyline segment (index i = vertex i to i+1).
    public let segmentBearings: [Double]
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

        Self.alignTurns(&steps, polyline: polyline, cumulative: cum)
        Self.neutralizeStart(&steps, polyline: polyline)

        self.polyline = polyline
        self.cumulative = cum
        self.segmentBearings = (0..<(polyline.count - 1)).map { Geo.bearing(from: polyline[$0], to: polyline[$0 + 1]) }
        self.steps = steps
        self.duration = duration
    }
}

extension Route {
    /// Makes each turn agree with the line the car actually follows. If a step says left but the route geometry at that
    /// point clearly turns right (or the reverse), the geometry wins: the arrow, the spoken words and the road all match.
    static func alignTurns(_ steps: inout [RouteStep], polyline: [Coordinate], cumulative: [Double], window: Double = 30, minimumAngle: Double = 40) {
        func point(at offset: Double) -> Coordinate {
            let d = min(max(offset, 0), cumulative[cumulative.count - 1])
            var lo = 0, hi = cumulative.count - 2
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if cumulative[mid] <= d { lo = mid } else { hi = mid - 1 }
            }
            let length = cumulative[lo + 1] - cumulative[lo]
            let t = length > 0 ? (d - cumulative[lo]) / length : 0
            let a = polyline[lo], b = polyline[lo + 1]
            return Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
        }
        let turns: Set<Maneuver> = [.turnSlightLeft, .turnLeft, .turnSharpLeft, .turnSlightRight, .turnRight, .turnSharpRight]
        for i in steps.indices.dropFirst() where turns.contains(steps[i].maneuver) {
            let at = steps[i].startOffset
            let before = point(at: at - window), here = point(at: at), after = point(at: at + window)
            guard Geo.distance(before, here) > 5, Geo.distance(here, after) > 5 else { continue }
            let angle = Geo.turnAngle(before: Geo.bearing(from: before, to: here), after: Geo.bearing(from: here, to: after))
            guard abs(angle) >= minimumAngle else { continue }
            let geometryIsRight = angle > 0
            let statedIsRight = steps[i].maneuver.rawValue.contains("RIGHT")
            guard geometryIsRight != statedIsRight else { continue }
            steps[i].maneuver = Maneuver.classify(turnAngle: angle)
            steps[i].instruction = swapSide(in: steps[i].instruction)
        }
    }

    /// Apple Maps plans from a bare coordinate, so a "turn left/right" as the very first step assumes a heading the car may not have.
    /// Say which way the route heads off instead ("Head south on N Glebe Rd") and leave the side to the road itself.
    static func neutralizeStart(_ steps: inout [RouteStep], polyline: [Coordinate]) {
        let turns: Set<Maneuver> = [.turnSlightLeft, .turnLeft, .turnSharpLeft, .turnSlightRight, .turnRight, .turnSharpRight]
        guard let first = steps.first, turns.contains(first.maneuver), polyline.count >= 2 else { return }
        let far = polyline.dropFirst().first { Geo.distance(polyline[0], $0) >= 15 } ?? polyline[polyline.count - 1]
        let bearing = (Geo.bearing(from: polyline[0], to: far).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let names = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let direction = names[Int((bearing + 22.5) / 45) % 8]
        var text = "Head \(direction)"
        if let range = first.instruction.range(of: " onto ") { text += " on " + first.instruction[range.upperBound...] }
        steps[0].instruction = text
        steps[0].maneuver = .straight
    }

    /// "Your destination is on the left" is corrected from where the destination point really lies relative to the end of the
    /// route (left or right of the direction of travel). Does nothing when the point is too close to tell.
    public static func correctedArrival(_ instruction: String, routeEnd: Coordinate, travelBearing: Double, destination: Coordinate, minimum: Double = 8) -> String {
        let north = (destination.latitude - routeEnd.latitude) * 111_320
        let east = (destination.longitude - routeEnd.longitude) * 111_320 * cos(routeEnd.latitude * .pi / 180)
        guard (north * north + east * east).squareRoot() >= minimum else { return instruction }
        let b = travelBearing * .pi / 180
        let cross = sin(b) * north - cos(b) * east   // negative: destination lies to the right of travel
        let isRight = cross < 0
        let lower = instruction.lowercased()
        let mentionsRight = lower.contains("right"), mentionsLeft = lower.contains("left")
        guard mentionsRight != mentionsLeft, mentionsRight != isRight else { return instruction }
        return swapSide(in: instruction)
    }

    /// "Turn right onto Elm St" becomes "Turn left onto Elm St" (first whole word only, keeping capitalization).
    static func swapSide(in text: String) -> String {
        guard let range = text.range(of: "\\b(left|right)\\b", options: [.regularExpression, .caseInsensitive]) else { return text }
        let word = String(text[range])
        let swapped = word.lowercased() == "left" ? "right" : "left"
        let replacement = word.first?.isUppercase == true ? swapped.prefix(1).uppercased() + swapped.dropFirst() : swapped
        return text.replacingCharacters(in: range, with: replacement)
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
