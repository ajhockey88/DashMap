import SwiftUI
import DashMapCore

/// Windshield-reflection HUD: black background, high-contrast glyphs, optionally mirrored horizontally.
struct HUDView: View {
    @EnvironmentObject private var session: NavigationSession
    @Binding var hud: Bool
    @AppStorage("hud.mirrored") private var mirrored = true
    @AppStorage("hud.style") private var style = "arrows"   // "arrows" or "map"
    @State private var following = true
    @AppStorage("units") private var unitsSetting = "auto"
    @State private var showEnd = false
    @State private var previousBrightness = UIScreen.main.brightness

    private var units: Units { Units(setting: unitsSetting) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            Group {
                if style == "map" { mapDisplay } else { arrowsDisplay }
            }
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

    private var arrowsDisplay: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            if let s = session.state {
                Image(systemName: session.displayManeuver(for: s).symbolName)
                    .font(.system(size: 150, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(units.distance(s.distanceToManeuver))
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                Text(s.nextInstruction)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal)
                if let exit = session.exitInfo?.summary {
                    Label(exit, systemImage: "signpost.right.fill")
                        .font(.title3.weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(1)
                } else if s.distanceToManeuver > 1_000, let road = session.roadInfo?.title {
                    Text("Continue on \(road) for \(units.distance(s.distanceToManeuver))")
                        .font(.title3).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                if let lanes = session.activeLanes {
                    LaneStrip(guidance: lanes, scale: 1.3)
                }
                if let then = s.thenManeuver {
                    Label(s.thenInstruction ?? "", systemImage: then.symbolName)
                        .font(.title3).lineLimit(1).foregroundStyle(.secondary)
                }
                if let road = session.roadInfo { RoadChip(info: road, large: true) }
                if session.gpsLost {
                    Label("GPS lost – estimating", systemImage: "location.slash").font(.footnote).foregroundStyle(.yellow)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 32) {
                    let sp = units.speed(session.speed)
                    stat("\(sp.value)", sp.unit, big: true, warn: session.isSpeeding)
                    if let kph = session.roadInfo?.speedLimitKph { SpeedLimitSign(kph: kph, units: units, size: 56) }
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

    /// Dark, high-contrast moving map with a compact turn banner and speed; mirrored together with the HUD.
    private var mapDisplay: some View {
        ZStack {
            DrivingMap(
                style: .hud,
                route: session.route,
                state: session.state,
                car: session.carPosition,
                heading: session.carHeading,
                speed: session.speed,
                lanePaint: session.activeLanePaint,
                following: $following
            )
            .ignoresSafeArea()

            VStack {
                if let s = session.state {
                    HStack(spacing: 14) {
                        Image(systemName: session.displayManeuver(for: s).symbolName)
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(units.distance(s.distanceToManeuver))
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                            Text(s.nextInstruction).font(.callout.weight(.semibold)).lineLimit(1)
                            if let exit = session.exitInfo?.summary {
                                Text(exit).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 12)
                    .padding(.top, 100)
                }
                if let lanes = session.activeLanes {
                    LaneStrip(guidance: lanes)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 8)
                }
                if let road = session.roadInfo { RoadChip(info: road).padding(.top, 8) }
                Spacer()
                if let s = session.state {
                    HStack(alignment: .firstTextBaseline, spacing: 28) {
                        let sp = units.speed(session.speed)
                        stat("\(sp.value)", sp.unit, big: true, warn: session.isSpeeding)
                    if let kph = session.roadInfo?.speedLimitKph { SpeedLimitSign(kph: kph, units: units, size: 56) }
                        stat(arrival(s.timeRemaining), "arrive")
                        stat(units.distance(s.distanceRemaining), "left")
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.78))
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(_ value: String, _ label: String, big: Bool = false, warn: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: big ? 72 : 36, weight: .bold, design: .rounded))
                .foregroundStyle(warn ? Theme.danger : .white)
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func arrival(_ secondsFromNow: Double) -> String {
        Date().addingTimeInterval(secondsFromNow).formatted(date: .omitted, time: .shortened)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { mirrored.toggle() } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .accessibilityLabel(mirrored ? "Mirrored, tap for normal" : "Normal, tap to mirror")
            Button { style = style == "map" ? "arrows" : "map" } label: {
                Image(systemName: style == "map" ? "map" : "arrow.up")
            }
            .accessibilityLabel(style == "map" ? "Map style, tap for arrows" : "Arrows style, tap for map")
            Button { unitsSetting = units.metric ? "imperial" : "metric" } label: { Text(units.metric ? "km" : "mi") }
            Button { session.voiceEnabled.toggle() } label: {
                Image(systemName: session.voiceEnabled ? "speaker.wave.2" : "speaker.slash")
            }
            .accessibilityLabel("Voice guidance")
            Spacer(minLength: 0)
            Button { hud = false } label: { Text("Nav") }
            Button { showEnd = true } label: { Image(systemName: "xmark.circle.fill") }
                .accessibilityLabel("End navigation")
        }
        .lineLimit(1)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(.gray)
        .padding(.horizontal, 12)
        .padding(.vertical)
        .confirmationDialog("End navigation?", isPresented: $showEnd, titleVisibility: .visible) {
            Button("End navigation", role: .destructive) { session.stopNavigation() }
            Button("Keep going", role: .cancel) {}
        }
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
