import SwiftUI
import MapKit
import DashMapCore

struct PreviewView: View {
    @EnvironmentObject private var session: NavigationSession

    var body: some View {
        ZStack(alignment: .bottom) {
            if let route = session.route {
                RouteMap(route: route).ignoresSafeArea(edges: .bottom)
                VStack(spacing: 12) {
                    let units = Units.localeDefault
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
    let route: Route

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        let coords = route.polyline.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let line = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(line)
        map.setVisibleMapRect(line.boundingMapRect, edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 160, right: 40), animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 6
            return renderer
        }
    }
}
