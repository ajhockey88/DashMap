import SwiftUI
import MapKit
import DashMapCore

struct PreviewView: View {
    @EnvironmentObject private var session: NavigationSession
    @AppStorage("units") private var unitsSetting = "auto"
    @AppStorage("nav.hud") private var startInHUD = false

    private var units: Units { Units(setting: unitsSetting) }

    var body: some View {
        ZStack {
            RouteMap(routes: session.routes, selected: session.selectedRouteIndex)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                sheet
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            IconButton(systemName: "chevron.left", label: "Back") { session.stopNavigation() }
            Text(session.destinationName)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface.opacity(0.95), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var sheet: some View {
        VStack(spacing: 14) {
            let fastest = session.routes.map(\.duration).min()
            ForEach(Array(session.routes.enumerated()), id: \.offset) { i, route in
                let selected = i == session.selectedRouteIndex
                Button { session.selectRoute(i) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(formatDuration(route.duration)).font(.title2.bold())
                                if route.duration == fastest {
                                    Text("Fastest")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Theme.onAccent)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Theme.accent, in: Capsule())
                                }
                            }
                            Text("\(units.distance(route.distance)) · arrive \(arrival(route.duration))")
                                .font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                    }
                    .padding(16)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Theme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            Picker("Display", selection: $startInHUD) {
                Text("Map").tag(false)
                Text("HUD").tag(true)
            }
            .pickerStyle(.segmented)

            Button("Start") { session.startNavigation() }
                .buttonStyle(PrimaryButtonStyle())

            Button("Simulate drive") { session.startNavigation(simulated: true) }
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .frame(minHeight: 44)
        }
        .padding(16)
        .padding(.bottom, 8)
        .background(Theme.surface, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
    }

    private func arrival(_ secondsFromNow: Double) -> String {
        Date().addingTimeInterval(secondsFromNow).formatted(date: .omitted, time: .shortened)
    }
}

private struct RouteMap: UIViewRepresentable {
    let routes: [Route]
    let selected: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.showsUserLocation = true
        map.showsTraffic = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        // Draw alternatives first so the selected route sits on top.
        var rect = MKMapRect.null
        for (i, route) in routes.enumerated().sorted(by: { $0.offset == selected ? false : ($1.offset == selected) }) {
            let line = MKPolyline(coordinates: route.mapCoordinates, count: route.polyline.count)
            line.title = i == selected ? "selected" : "alternate"
            map.addOverlay(line)
            rect = rect.union(line.boundingMapRect)
        }
        if !rect.isNull, context.coordinator.fitted != routes.count {
            context.coordinator.fitted = routes.count
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 100, left: 40, bottom: 420, right: 40), animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var fitted = 0
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            let selected = overlay.title == "selected"
            renderer.strokeColor = selected ? UIColor(red: 0.30, green: 0.60, blue: 1.0, alpha: 1) : UIColor(white: 0.5, alpha: 1)
            renderer.lineWidth = selected ? 8 : 5
            renderer.lineCap = .round
            return renderer
        }
    }
}

extension Route {
    var mapCoordinates: [CLLocationCoordinate2D] {
        polyline.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
