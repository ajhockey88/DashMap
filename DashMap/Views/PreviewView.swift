import SwiftUI
import GoogleMaps
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

    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView()
        map.isMyLocationEnabled = true
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        map.clear()
        let path = GMSMutablePath()
        route.polyline.forEach { path.add(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        let line = GMSPolyline(path: path)
        line.strokeWidth = 6
        line.strokeColor = .systemBlue
        line.map = map
        map.animate(with: GMSCameraUpdate.fit(GMSCoordinateBounds(path: path), withPadding: 60))
    }
}
