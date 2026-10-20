import Foundation

public struct NavigationState: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case onRoute, offRoute, arrived }

    public var status: Status
    /// Meters travelled along the route.
    public var progress: Double
    /// Distance from the raw location to the route line.
    public var offRouteDistance: Double
    public var snapped: Coordinate
    /// Index of the polyline segment the position is on.
    public var segment: Int
    public var stepIndex: Int
    public var nextManeuver: Maneuver
    public var nextInstruction: String
    public var distanceToManeuver: Double
    /// The maneuver after the next one, set only when it follows closely enough to warn about ("then turn left").
    public var thenManeuver: Maneuver?
    public var thenInstruction: String?
    public var distanceRemaining: Double
    public var timeRemaining: Double
    /// True when the position was estimated rather than measured.
    public var isEstimated: Bool
}

/// Matches GPS fixes to a route and derives guidance state. Not thread-safe; feed it from one queue.
public final class NavigationEngine {
    public let route: Route
    private var lastSegment = 0
    private var lastProgress = 0.0
    private var offRouteStrikes = 0

    static let searchAhead = 1_500.0
    static let arrivalRadius = 25.0
    static let thenDistance = 300.0
    /// Heading mismatch (in meters of equivalent offset) added when picking between candidate segments.
    static let headingPenalty = 30.0

    public init(route: Route) {
        self.route = route
    }

    /// - Parameters:
    ///   - course: direction of travel in degrees, if known; used to prefer the segment you're heading along.
    ///   - speed: m/s; course is only trusted above ~3 m/s.
    public func update(location: Coordinate, accuracy: Double = 10, course: Double? = nil, speed: Double = 0) -> NavigationState {
        let pts = route.polyline
        let cum = route.cumulative
        let lastIndex = pts.count - 2
        let useCourse = course != nil && speed > 3

        var best = (segment: lastSegment, t: 0.0, offset: Double.infinity, cost: Double.infinity)
        func consider(_ i: Int) {
            let r = Geo.project(location, onto: pts[i], pts[i + 1])
            var cost = r.offset
            if useCourse, let course {
                let diff = abs(Geo.turnAngle(before: course, after: route.segmentBearings[i]))
                cost += Self.headingPenalty * min(diff, 90) / 90
            }
            if cost < best.cost { best = (i, r.t, r.offset, cost) }
        }

        // Prefer a window just behind/ahead of the last match so loops and parallel roads don't cause jumps.
        var i = max(0, lastSegment - 2)
        let limit = cum[lastSegment] + Self.searchAhead
        while i <= lastIndex {
            consider(i)
            if cum[i + 1] > limit { break }
            i += 1
        }
        if best.offset > 100 {
            for j in 0...lastIndex { consider(j) }
        }

        lastSegment = best.segment
        let segLen = cum[best.segment + 1] - cum[best.segment]
        lastProgress = cum[best.segment] + best.t * segLen

        // Sustained deviation, not a single noisy fix. Far-off positions confirm faster.
        let threshold = max(35, accuracy * 2)
        if best.offset > threshold { offRouteStrikes += 1 } else { offRouteStrikes = 0 }
        let needed = best.offset > threshold * 3 ? 2 : 3
        let off = offRouteStrikes >= needed

        return makeState(progress: lastProgress, segment: best.segment, offset: best.offset, offRoute: off, estimated: false)
    }

    /// Dead reckoning: advance along the route from the last real fix when GPS drops out (tunnels, garages).
    public func extrapolate(speed: Double, since seconds: Double) -> NavigationState {
        let progress = min(route.distance, lastProgress + max(0, speed) * max(0, seconds))
        let cum = route.cumulative
        var seg = lastSegment
        while seg < cum.count - 2 && cum[seg + 1] < progress { seg += 1 }
        return makeState(progress: progress, segment: seg, offset: 0, offRoute: false, estimated: true)
    }

    private func makeState(progress: Double, segment: Int, offset: Double, offRoute: Bool, estimated: Bool) -> NavigationState {
        let pts = route.polyline
        let cum = route.cumulative
        let segLen = cum[segment + 1] - cum[segment]
        let t = segLen > 0 ? min(1, max(0, (progress - cum[segment]) / segLen)) : 0
        let a = pts[segment], b = pts[segment + 1]
        let snapped = Coordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )

        let steps = route.steps
        let stepIndex = steps.lastIndex(where: { $0.startOffset <= progress }) ?? 0
        let step = steps[stepIndex]
        let upcoming = stepIndex + 1 < steps.count ? steps[stepIndex + 1] : nil
        let following = stepIndex + 2 < steps.count ? steps[stepIndex + 2] : nil

        let stepLeft = max(0, step.endOffset - progress)
        let stepLength = step.endOffset - step.startOffset
        var timeRemaining = stepLength > 0 ? step.duration * stepLeft / stepLength : 0
        for s in steps[(stepIndex + 1)...] { timeRemaining += s.duration }
        let distanceRemaining = max(0, route.distance - progress)

        var thenManeuver: Maneuver?
        var thenInstruction: String?
        if let upcoming, let following, upcoming.endOffset - upcoming.startOffset <= Self.thenDistance {
            thenManeuver = following.maneuver
            thenInstruction = following.instruction
        }

        let status: NavigationState.Status
        if distanceRemaining < Self.arrivalRadius {
            status = .arrived
        } else if offRoute {
            status = .offRoute
        } else {
            status = .onRoute
        }

        return NavigationState(
            status: status,
            progress: progress,
            offRouteDistance: offset,
            snapped: snapped,
            segment: segment,
            stepIndex: stepIndex,
            nextManeuver: upcoming?.maneuver ?? .arrive,
            nextInstruction: upcoming?.instruction ?? "Arrive at your destination",
            distanceToManeuver: stepLeft,
            thenManeuver: thenManeuver,
            thenInstruction: thenInstruction,
            distanceRemaining: distanceRemaining,
            timeRemaining: timeRemaining,
            isEstimated: estimated
        )
    }
}

public struct Announcement: Equatable, Sendable {
    public enum Stage: Int, Sendable { case far = 1, near, arrive }

    public var stage: Stage
    public var maneuver: Maneuver
    public var instruction: String
    public var distance: Double
    /// Closely following instruction to chain on ("…, then turn left onto Main St").
    public var then: String?
}

/// Decides when to speak. Each (step, stage) is announced once; thresholds grow with speed.
public final class Announcer {
    private var lastStep = -1
    private var lastStage = 0

    public init() {}

    public func next(for state: NavigationState, speed: Double) -> Announcement? {
        if state.status == .offRoute { return nil }

        let stage: Announcement.Stage?
        if state.status == .arrived {
            stage = .arrive
        } else if state.distanceToManeuver <= max(120, speed * 10) {
            stage = .near
        } else if state.distanceToManeuver <= max(600, speed * 45) {
            stage = .far
        } else {
            stage = nil
        }

        if state.stepIndex != lastStep {
            lastStep = state.stepIndex
            lastStage = 0
        }
        guard let stage, stage.rawValue > lastStage else { return nil }
        lastStage = stage.rawValue
        return Announcement(
            stage: stage,
            maneuver: state.nextManeuver,
            instruction: state.nextInstruction,
            distance: state.distanceToManeuver,
            then: stage == .arrive ? nil : state.thenInstruction
        )
    }
}
