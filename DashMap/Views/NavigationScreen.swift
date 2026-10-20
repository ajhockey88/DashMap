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
    @State private var recenter = 0

    private var units: Units { Units(metric: metric) }

    var body: some View {
        ZStack {
            FollowMap(route: session.route, state: session.state, recenter: recenter)
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
            Button { recenter += 1 } label: { Image(systemName: "location.fill") }
            Button { session.voiceEnabled.toggle() } label: {
                Image(systemName: session.voiceEnabled ? "speaker.wave.2" : "speaker.slash")
            }
            Button { hud = true } label: { Image(systemName: "rectangle.on.rectangle") }
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

/// Map camera that tracks the car's heading; the traveled part of the route turns gray.
private struct FollowMap: UIViewRepresentable {
    let route: Route?
    let state: NavigationState?
    let recenter: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsTraffic = true
        map.userTrackingMode = .followWithHeading
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        if c.recenter != recenter {
            c.recenter = recenter
            map.setUserTrackingMode(.followWithHeading, animated: true)
        }
        guard let route else { return }

        let segment = state?.segment ?? 0
        let key = "\(route.polyline.count)-\(route.distance)-\(segment)"
        guard key != c.overlayKey else { return }
        c.overlayKey = key

        map.removeOverlays(map.overlays)
        let all = route.mapCoordinates
        var done = Array(all[0...min(segment, all.count - 1)])
        var rest = Array(all[min(segment + 1, all.count - 1)...])
        if let snapped = state?.snapped {
            let p = CLLocationCoordinate2D(latitude: snapped.latitude, longitude: snapped.longitude)
            done.append(p)
            rest.insert(p, at: 0)
        }
        let traveled = MKPolyline(coordinates: done, count: done.count)
        traveled.title = "traveled"
        let remaining = MKPolyline(coordinates: rest, count: rest.count)
        remaining.title = "remaining"
        map.addOverlays([traveled, remaining])
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var recenter = 0
        var overlayKey = ""
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = overlay.title == "traveled" ? .systemGray3 : .systemBlue
            renderer.lineWidth = 8
            return renderer
        }
    }
}
