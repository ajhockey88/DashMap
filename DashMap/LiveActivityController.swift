import ActivityKit
import DashMapCore
import Foundation

/// Shows the next turn on the lock screen and Dynamic Island while navigating.
@MainActor
final class LiveActivityController {
    private var activity: Activity<NavigationActivityAttributes>?
    private var lastState: NavigationActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast

    func update(from s: NavigationState, maneuver: Maneuver, destination: String, units: Units) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = NavigationActivityAttributes.ContentState(
            symbolName: maneuver.symbolName,
            distanceText: units.distance(s.distanceToManeuver),
            instruction: s.nextInstruction,
            etaText: "\(formatDuration(s.timeRemaining)) · arrive \(Date().addingTimeInterval(s.timeRemaining).formatted(date: .omitted, time: .shortened))"
        )
        guard state != lastState, Date().timeIntervalSince(lastUpdate) > 2 else { return }   // the system rate-limits updates
        lastState = state
        lastUpdate = Date()

        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            activity = try? Activity.request(
                attributes: NavigationActivityAttributes(destination: destination),
                content: ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    func end() {
        let finished = activity
        activity = nil
        lastState = nil
        Task { await finished?.end(nil, dismissalPolicy: .immediate) }
    }
}
