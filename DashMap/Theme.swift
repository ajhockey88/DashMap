import SwiftUI

/// One dark palette for the whole app: near-black surfaces, a single mint accent that matches the HUD.
enum Theme {
    static let accent = Color(red: 0.29, green: 0.94, blue: 0.63)
    static let onAccent = Color.black
    static let background = Color(red: 0.04, green: 0.06, blue: 0.06)
    static let surface = Color(red: 0.09, green: 0.11, blue: 0.11)
    static let surfaceRaised = Color(red: 0.14, green: 0.17, blue: 0.17)
    static let secondary = Color(white: 0.68)
    static let route = Color(red: 0.30, green: 0.60, blue: 1.0)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.40)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// 48 pt round icon button with an accessibility label; `highlighted` fills it with the accent.
struct IconButton: View {
    let systemName: String
    let label: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(highlighted ? Theme.onAccent : .white)
                .frame(width: 48, height: 48)
                .background(highlighted ? Theme.accent : Theme.surfaceRaised, in: Circle())
        }
        .accessibilityLabel(label)
    }
}
