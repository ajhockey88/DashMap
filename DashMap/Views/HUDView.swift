import SwiftUI
import DashMapCore

/// Windshield-reflection HUD: black background, high-contrast glyphs, optionally mirrored horizontally.
struct HUDView: View {
    @EnvironmentObject private var session: NavigationSession
    @Binding var hud: Bool
    @AppStorage("hud.mirrored") private var mirrored = true
    @AppStorage("hud.metric") private var metric = Units.localeDefault.metric
    @State private var previousBrightness = UIScreen.main.brightness

    private var units: Units { Units(metric: metric) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            display
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)

            controls
        }
        .statusBarHidden(true)
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var display: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            if let s = session.state {
                Image(systemName: s.nextManeuver.symbolName)
                    .font(.system(size: 150, weight: .bold))
                    .foregroundStyle(.green)
                Text(units.distance(s.distanceToManeuver))
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                Text(s.nextInstruction)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal)
                if let then = s.thenManeuver {
                    Label(s.thenInstruction ?? "", systemImage: then.symbolName)
                        .font(.title3).lineLimit(1).foregroundStyle(.secondary)
                }
                if session.gpsLost {
                    Label("GPS lost – estimating", systemImage: "location.slash").font(.footnote).foregroundStyle(.yellow)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 32) {
                    let sp = units.speed(session.speed)
                    stat("\(sp.value)", sp.unit, big: true)
                    stat(arrival(s.timeRemaining), "arrive")
                    stat(units.distance(s.distanceRemaining), "left")
                }
            } else {
                ProgressView().tint(.white).scaleEffect(2)
            }
            Spacer(minLength: 24)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(_ value: String, _ label: String, big: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: big ? 72 : 36, weight: .bold, design: .rounded))
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func arrival(_ secondsFromNow: Double) -> String {
        Date().addingTimeInterval(secondsFromNow).formatted(date: .omitted, time: .shortened)
    }

    private var controls: some View {
        HStack {
            Button { mirrored.toggle() } label: {
                Label(mirrored ? "Mirrored" : "Normal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            Button { metric.toggle() } label: { Text(metric ? "km" : "mi") }
            Button { session.voiceEnabled.toggle() } label: {
                Image(systemName: session.voiceEnabled ? "speaker.wave.2" : "speaker.slash")
            }
            Spacer()
            Button { hud = false } label: { Image(systemName: "map") }
            Button { session.stopNavigation() } label: { Image(systemName: "xmark.circle.fill") }
        }
        .buttonStyle(.bordered)
        .tint(.gray)
        .padding()
    }
}

extension Maneuver {
    var symbolName: String {
        switch self {
        case .turnLeft: return "arrow.turn.up.left"
        case .turnRight: return "arrow.turn.up.right"
        case .turnSlightLeft, .forkLeft, .rampLeft: return "arrow.up.left"
        case .turnSlightRight, .forkRight, .rampRight: return "arrow.up.right"
        case .turnSharpLeft: return "arrow.turn.down.left"
        case .turnSharpRight: return "arrow.turn.down.right"
        case .uturnLeft: return "arrow.uturn.left"
        case .uturnRight: return "arrow.uturn.right"
        case .merge: return "arrow.merge"
        case .roundaboutLeft, .roundaboutRight: return "arrow.triangle.2.circlepath"
        case .ferry, .ferryTrain: return "ferry"
        case .arrive: return "flag.checkered"
        case .straight, .unspecified: return "arrow.up"
        }
    }
}
