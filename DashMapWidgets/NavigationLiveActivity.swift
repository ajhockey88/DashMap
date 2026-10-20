import ActivityKit
import SwiftUI
import WidgetKit

private let mint = Color(red: 0.29, green: 0.94, blue: 0.63)

@main
struct DashMapWidgets: WidgetBundle {
    var body: some Widget { NavigationLiveActivity() }
}

/// Next turn on the lock screen and in the Dynamic Island while navigating.
struct NavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.symbolName)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(mint)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.distanceText).font(.title2.weight(.bold))
                    Text(context.state.instruction).font(.subheadline).lineLimit(2)
                    Text(context.state.etaText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.85))
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbolName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(mint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.distanceText).font(.title2.weight(.bold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.instruction).font(.subheadline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.etaText).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName).foregroundStyle(mint)
            } compactTrailing: {
                Text(context.state.distanceText).font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: context.state.symbolName).foregroundStyle(mint)
            }
        }
    }
}
