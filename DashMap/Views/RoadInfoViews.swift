import SwiftUI
import DashMapCore

/// Current road: a route-number shield (for highways) and the street name.
struct RoadChip: View {
    let info: RoadInfo
    var large = false

    var body: some View {
        if let title = info.title {
            HStack(spacing: 8) {
                if let ref = info.ref, info.name != nil || info.isHighway {
                    Text(ref)
                        .font((large ? Font.subheadline : .caption).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(info.isHighway ? Color(red: 0.12, green: 0.32, blue: 0.7) : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
                }
                if info.name != nil || info.ref == nil || !info.isHighway {
                    Text(title).font((large ? Font.title3 : .subheadline).weight(.semibold)).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, large ? 8 : 6)
            .background(Theme.surface.opacity(0.96), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current road \(title)")
        }
    }
}

/// White circle with a red ring, in the user's units (rounded to the nearest 5 for miles).
struct SpeedLimitSign: View {
    let kph: Double
    let units: Units
    var size: CGFloat = 60

    var body: some View {
        let value = units.metric ? Int(kph.rounded()) : Int((kph / 1.609344 / 5).rounded() * 5)
        Text("\(value)")
            .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(.white, in: Circle())
            .overlay(Circle().stroke(Color.red, lineWidth: size * 0.1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed limit \(value) \(units.metric ? "kilometers per hour" : "miles per hour")")
    }
}
