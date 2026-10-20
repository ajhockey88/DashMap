import SwiftUI
import MapKit
import DashMapCore

struct PreviewView: View {
    @EnvironmentObject private var session: NavigationSession

    var body: some View {
        ZStack(alignment: .bottom) {
            if let route = session.route {
                RouteMap(routes: session.routes, selected: session.selectedRouteIndex).ignoresSafeArea(edges: .bottom)
                VStack(spacing: 12) {
                    let units = Units.localeDefault
                    if session.routes.count > 1 {
                        Picker("Route", selection: Binding(
                            get: { session.selectedRouteIndex },
                            set: { session.selectRoute($0) }
                        )) {
                            ForEach(Array(session.routes.enumerated()), id: \.offset) { i, r in
                                Text(formatDuration(r.duration)).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    Text("\(formatDuration(route.duration)) · \(units.distance(route.distance))")
                        .font(.headline)
                    HStack {
                        Button("Cancel", role: .cancel) { session.stopNavigation() }
                            .buttonStyle(.bordered)
                        Button("Start HUD") { session.startNavigation() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
        }
    }
}

private struct RouteMap: UIViewRepresentable {
    let routes: [Route]
    let selected: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
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
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 200, right: 40), animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var fitted = 0
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            let selected = overlay.title == "selected"
            renderer.strokeColor = selected ? .systemBlue : .systemGray
            renderer.lineWidth = selected ? 7 : 5
            return renderer
        }
    }
}

extension Route {
    var mapCoordinates: [CLLocationCoordinate2D] {
        polyline.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
