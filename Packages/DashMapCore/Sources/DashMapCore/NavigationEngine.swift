import Foundation

public struct NavigationState: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case onRoute, offRoute, arrived }

    public var status: Status
    /// Meters travelled along the route.
    public var progress: Double
    /// Distance from the raw location to the route line.
    public var offRouteDistance: Double
    public var snapped: Coordinate
    public var stepIndex: Int
    public var nextManeuver: Maneuver
    public var nextInstruction: String
    public var distanceToManeuver: Double
    public var distanceRemaining: Double
    public var timeRemaining: Double
}

/// Matches GPS fixes to a route and derives guidance state. Not thread-safe; feed it from one queue.
public final class NavigationEngine {
    public let route: Route
    private var lastSegment = 0
    private var offRouteStrikes = 0

    static let searchAhead = 1_500.0
    static let arrivalRadius = 25.0
    static let strikesBeforeReroute = 3

    public init(route: Route) {
        self.route = route
    }

    public func update(location: Coordinate, accuracy: Double = 10) -> NavigationState {
        let pts = route.polyline
        let cum = route.cumulative
        let lastIndex = pts.count - 2

        var best = (segment: lastSegment, t: 0.0, offset: Double.infinity)
        func consider(_ i: Int) {
            let r = Geo.project(location, onto: pts[i], pts[i + 1])
            if r.offset < best.offset { best = (i, r.t, r.offset) }
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
        let progress = cum[best.segment] + best.t * segLen
        let a = pts[best.segment], b = pts[best.segment + 1]
        let snapped = Coordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * best.t,
            longitude: a.longitude + (b.longitude - a.longitude) * best.t
        )

        let steps = route.steps
        let stepIndex = steps.lastIndex(where: { $0.startOffset <= progress }) ?? 0
        let step = steps[stepIndex]
        let upcoming = stepIndex + 1 < steps.count ? steps[stepIndex + 1] : nil

        let stepLeft = max(0, step.endOffset - progress)
        let stepLength = step.endOffset - step.startOffset
        var timeRemaining = stepLength > 0 ? step.duration * stepLeft / stepLength : 0
        for s in steps[(stepIndex + 1)...] { timeRemaining += s.duration }
        let distanceRemaining = max(0, route.distance - progress)

        let threshold = max(35, accuracy * 2)
        if best.offset > threshold { offRouteStrikes += 1 } else { offRouteStrikes = 0 }

        let status: NavigationState.Status
        if distanceRemaining < Self.arrivalRadius {
            status = .arrived
        } else if offRouteStrikes >= Self.strikesBeforeReroute {
            status = .offRoute
        } else {
            status = .onRoute
        }

        return NavigationState(
            status: status,
            progress: progress,
            offRouteDistance: best.offset,
            snapped: snapped,
            stepIndex: stepIndex,
            nextManeuver: upcoming?.maneuver ?? .arrive,
            nextInstruction: upcoming?.instruction ?? "Arrive at your destination",
            distanceToManeuver: stepLeft,
            distanceRemaining: distanceRemaining,
            timeRemaining: timeRemaining
        )
    }
}

public struct Announcement: Equatable, Sendable {
    public enum Stage: Int, Sendable { case far = 1, near, arrive }

    public var stage: Stage
    public var maneuver: Maneuver
    public var instruction: String
    public var distance: Double
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
            distance: state.distanceToManeuver
        )
    }
}
