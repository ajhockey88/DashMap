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
    @AppStorage("units") private var unitsSetting = "auto"
    @State private var following = true
    @State private var showEnd = false

    private var units: Units { Units(setting: unitsSetting) }

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
                HStack(alignment: .bottom) {
                    speedBadge
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                bottomBar
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog("End navigation?", isPresented: $showEnd, titleVisibility: .visible) {
            Button("End navigation", role: .destructive) { session.stopNavigation() }
            Button("Keep going", role: .cancel) {}
        }
    }

    @ViewBuilder private var banner: some View {
        if let s = session.state {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Image(systemName: s.nextManeuver.symbolName)
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(units.distance(s.distanceToManeuver))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text(s.nextInstruction).font(.headline).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                if let then = s.thenManeuver {
                    Divider().overlay(.white.opacity(0.2))
                    Label("Then " + (s.thenInstruction ?? ""), systemImage: then.symbolName)
                        .font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                if let lanes = session.activeLanes {
                    LaneStrip(guidance: lanes)
                }
                if session.gpsLost {
                    Label("GPS signal lost. Estimating position.", systemImage: "location.slash")
                        .font(.footnote).foregroundStyle(.yellow)
                }
            }
            .padding(16)
            .background(Theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    private var speedBadge: some View {
        let sp = units.speed(session.speed)
        return VStack(spacing: 0) {
            Text("\(sp.value)").font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
            Text(sp.unit).font(.caption2).foregroundStyle(Theme.secondary)
        }
        .frame(width: 68, height: 68)
        .background(Theme.surface.opacity(0.96), in: Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed \(sp.value) \(sp.unit)")
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let s = session.state {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDuration(s.timeRemaining)).font(.title2.bold()).foregroundStyle(Theme.accent)
                    Text("\(units.distance(s.distanceRemaining)) · \(arrival(s.timeRemaining))")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            IconButton(systemName: following ? "location.fill" : "location", label: "Recenter map", highlighted: !following) {
                following = true
            }
            IconButton(systemName: session.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", label: "Voice guidance") {
                session.voiceEnabled.toggle()
            }
            IconButton(systemName: "speedometer", label: "Switch to HUD") { hud = true }
            Button { showEnd = true } label: {
                Text("End")
                    .font(.headline)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(Theme.surfaceRaised, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Theme.surface.opacity(0.96), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
    }

    private func arrival(_ secondsFromNow: Double) -> String {
        Date().addingTimeInterval(secondsFromNow).formatted(date: .omitted, time: .shortened)
    }
}
