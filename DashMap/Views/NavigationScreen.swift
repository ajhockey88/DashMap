import SwiftUI
import MapKit
import DashMapCore

/// Hosts the two driving displays: a map that follows the car, and the windshield HUD.
struct NavigationScreen: View {
    @EnvironmentObject private var session: NavigationSession
    @AppStorage("nav.hud") private var hud = false

    var body: some View {
        if hud { HUDView(hud: $hud) } else { MapNavView(hud: $hud) }
    }
}

private struct MapNavView: View {
    @EnvironmentObject private var session: NavigationSession
    @Binding var hud: Bool
    @AppStorage("hud.metric") private var metric = Units.localeDefault.metric
    @State private var following = true

    private var units: Units { Units(metric: metric) }

    var body: some View {
        ZStack {
            DrivingMap(
                style: .standard,
                route: session.route,
                state: session.state,
                car: session.carPosition,
                heading: session.carHeading,
                speed: session.speed,
                following: $following
            )
            .ignoresSafeArea()
            VStack(spacing: 0) {
                banner
                Spacer()
                bottomBar
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var banner: some View {
        Group {
            if let s = session.state {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 16) {
                        Image(systemName: s.nextManeuver.symbolName).font(.system(size: 44, weight: .bold))
                        VStack(alignment: .leading) {
                            Text(units.distance(s.distanceToManeuver)).font(.system(size: 34, weight: .bold, design: .rounded))
                            Text(s.nextInstruction).font(.headline).lineLimit(2)
                        }
                        Spacer()
                    }
                    if let then = s.thenManeuver {
                        Label(s.thenInstruction ?? "", systemImage: then.symbolName)
                            .font(.subheadline).lineLimit(1).foregroundStyle(.white.opacity(0.85))
                    }
                    if session.gpsLost {
                        Label("GPS signal lost – estimating position", systemImage: "location.slash")
                            .font(.caption).foregroundStyle(.yellow)
                    }
                }
                .padding()
                .foregroundStyle(.white)
                .background(Color(red: 0.05, green: 0.45, blue: 0.3), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 20) {
            if let s = session.state {
                VStack(alignment: .leading) {
                    Text(formatDuration(s.timeRemaining)).font(.title3.bold())
                    Text("\(units.distance(s.distanceRemaining)) · \(arrival(s.timeRemaining))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            let sp = units.speed(session.speed)
            Text("\(sp.value) \(sp.unit)").font(.headline.monospacedDigit())
            Button { following = true } label: {
                Image(systemName: following ? "location.fill" : "location")
            }
            .tint(following ? .gray : .blue)
            Button { session.voiceEnabled.toggle() } label: {
                Image(systemName: session.voiceEnabled ? "speaker.wave.2" : "speaker.slash")
            }
            Button { hud = true } label: { Text("HUD") }
            Button(role: .destructive) { session.stopNavigation() } label: { Image(systemName: "xmark") }
        }
        .buttonStyle(.bordered)
        .padding()
        .background(.regularMaterial)
    }

    private func arrival(_ secondsFromNow: Double) -> String {
        Date().addingTimeInterval(secondsFromNow).formatted(date: .omitted, time: .shortened)
    }
}
