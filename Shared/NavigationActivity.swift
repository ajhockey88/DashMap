import ActivityKit
import Foundation

/// Shared by the app (which starts and updates the activity) and the widget extension (which draws it).
struct NavigationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// SF Symbol for the next maneuver.
        var symbolName: String
        var distanceText: String
        var instruction: String
        var etaText: String
    }

    var destination: String
}
