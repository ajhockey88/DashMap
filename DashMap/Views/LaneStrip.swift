import SwiftUI
import DashMapCore

/// Road lanes as seen from the driver's seat: usable lanes are bright, the others dimmed.
struct LaneStrip: View {
    let guidance: LaneGuidance
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 6 * scale) {
            ForEach(Array(guidance.lanes.enumerated()), id: \.offset) { _, lane in
                HStack(spacing: 0) {
                    ForEach(Array(symbols(for: lane).enumerated()), id: \.offset) { _, name in
                        Image(systemName: name).font(.system(size: 16 * scale, weight: .bold))
                    }
                }
                .foregroundStyle(lane.isRecommended ? Theme.onAccent : Theme.secondary)
                .frame(minWidth: 36 * scale, minHeight: 50 * scale)
                .padding(.horizontal, 4 * scale)
                .background(
                    lane.isRecommended ? Theme.accent : Theme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 8 * scale)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func symbols(for lane: Lane) -> [String] {
        let named = lane.indications.filter { $0 != .none }
        return named.isEmpty ? [LaneIndication.through.symbolName] : named.map(\.symbolName)
    }

    private var summary: String {
        let positions = guidance.recommendedPositions.map { "\($0 + 1)" }.joined(separator: " and ")
        return "\(guidance.lanes.count) lanes. Use lane \(positions) from the left."
    }
}

extension LaneIndication {
    var symbolName: String {
        switch self {
        case .left, .mergeToLeft: return "arrow.turn.up.left"
        case .sharpLeft: return "arrow.turn.down.left"
        case .slightLeft: return "arrow.up.left"
        case .through, .none: return "arrow.up"
        case .slightRight: return "arrow.up.right"
        case .right, .mergeToRight: return "arrow.turn.up.right"
        case .sharpRight: return "arrow.turn.down.right"
        case .reverse: return "arrow.uturn.left"
        }
    }
}
