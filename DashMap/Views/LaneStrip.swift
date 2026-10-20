import SwiftUI
import DashMapCore

/// Lanes drawn like Google Maps: bare arrows, white for the lanes you can use and dimmed for the rest.
/// A lane that allows several directions is one arrow with a branch for each.
struct LaneStrip: View {
    let guidance: LaneGuidance
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 2 * scale) {
            ForEach(Array(guidance.lanes.enumerated()), id: \.offset) { _, lane in
                LaneGlyph(indications: lane.indications)
                    .stroke(
                        Color.white.opacity(lane.isRecommended ? 1 : 0.4),
                        style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 28 * scale, height: 40 * scale)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        let positions = guidance.recommendedPositions.map { "\($0 + 1)" }.joined(separator: " and ")
        return "\(guidance.lanes.count) lanes. Use lane \(positions) from the left."
    }
}

/// One lane's arrow: a stem from the bottom with a branch and arrowhead for every allowed direction.
struct LaneGlyph: Shape {
    let indications: [LaneIndication]

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX
        let marked = indications.filter { $0 != .none }
        let branches = marked.isEmpty ? [LaneIndication.through] : marked

        var path = Path()
        let base = CGPoint(x: cx, y: rect.maxY - h * 0.04)
        let fork = CGPoint(x: cx, y: rect.minY + h * 0.56)
        path.move(to: base)
        path.addLine(to: fork)

        for indication in branches {
            switch indication {
            case .through, .none:
                let end = CGPoint(x: cx, y: rect.minY + h * 0.08)
                path.move(to: fork); path.addLine(to: end)
                head(&path, at: end, direction: CGPoint(x: 0, y: -1), size: w * 0.26)
            case .left, .mergeToLeft:
                turn(&path, from: fork, sign: -1, w: w, h: h, rect: rect)
            case .right, .mergeToRight:
                turn(&path, from: fork, sign: 1, w: w, h: h, rect: rect)
            case .slightLeft:
                diagonal(&path, from: fork, sign: -1, w: w, h: h)
            case .slightRight:
                diagonal(&path, from: fork, sign: 1, w: w, h: h)
            case .sharpLeft:
                sharp(&path, from: fork, sign: -1, w: w, h: h)
            case .sharpRight:
                sharp(&path, from: fork, sign: 1, w: w, h: h)
            case .reverse:
                let top = rect.minY + h * 0.14
                let end = CGPoint(x: cx - w * 0.3, y: rect.minY + h * 0.5)
                path.move(to: fork)
                path.addLine(to: CGPoint(x: cx, y: top + w * 0.3))
                path.addQuadCurve(to: CGPoint(x: cx - w * 0.3, y: top + w * 0.3), control: CGPoint(x: cx - w * 0.15, y: top - w * 0.12))
                path.addLine(to: end)
                head(&path, at: end, direction: CGPoint(x: 0, y: 1), size: w * 0.26)
            }
        }
        return path
    }

    /// A 90 degree turn: up, then bending sideways, with the arrowhead pointing sideways.
    private func turn(_ path: inout Path, from fork: CGPoint, sign: CGFloat, w: CGFloat, h: CGFloat, rect: CGRect) {
        let y = rect.minY + h * 0.26
        let end = CGPoint(x: fork.x + sign * w * 0.40, y: y)
        path.move(to: fork)
        path.addLine(to: CGPoint(x: fork.x, y: y + w * 0.2))
        path.addQuadCurve(to: CGPoint(x: fork.x + sign * w * 0.2, y: y), control: CGPoint(x: fork.x, y: y))
        path.addLine(to: end)
        head(&path, at: end, direction: CGPoint(x: sign, y: 0), size: w * 0.26)
    }

    private func diagonal(_ path: inout Path, from fork: CGPoint, sign: CGFloat, w: CGFloat, h: CGFloat) {
        let end = CGPoint(x: fork.x + sign * w * 0.34, y: fork.y - h * 0.42)
        path.move(to: fork); path.addLine(to: end)
        head(&path, at: end, direction: CGPoint(x: sign * 0.62, y: -0.78), size: w * 0.26)
    }

    private func sharp(_ path: inout Path, from fork: CGPoint, sign: CGFloat, w: CGFloat, h: CGFloat) {
        let end = CGPoint(x: fork.x + sign * w * 0.38, y: fork.y - h * 0.06)
        path.move(to: fork); path.addLine(to: end)
        head(&path, at: end, direction: CGPoint(x: sign * 0.95, y: -0.3), size: w * 0.26)
    }

    /// Open arrowhead at `point`, pointing along `direction`.
    private func head(_ path: inout Path, at point: CGPoint, direction: CGPoint, size: CGFloat) {
        let angle = atan2(direction.y, direction.x)
        for side in [-1.0, 1.0] {
            let a = angle + .pi + side * 0.62
            path.move(to: point)
            path.addLine(to: CGPoint(x: point.x + size * cos(a), y: point.y + size * sin(a)))
        }
    }
}
