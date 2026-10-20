import MapKit
import DashMapCore

struct StopResult: Identifiable {
    let item: MKMapItem
    /// Meters from your position along the route to the point nearest the place.
    let distanceAhead: Double
    /// Meters from the route to the place.
    let sideDistance: Double
    var id: String { "\(item.name ?? "")|\(item.placemark.coordinate.latitude)|\(item.placemark.coordinate.longitude)" }

    /// Rough extra drive time (there and back at a typical city speed); the exact figure comes from routing.
    var roughDetourMinutes: Int { max(1, Int((2 * sideDistance / 11 / 60).rounded())) }
}

/// A chosen stop, routed: your position → stop → destination.
struct StopPlan {
    let item: MKMapItem
    let route: Route
    let joinOffset: Double
    /// Seconds added to the trip.
    let added: Double
}

enum StopCategory: CaseIterable, Identifiable {
    case gas, food, coffee, charging, parking

    var id: Self { self }
    var title: String {
        switch self {
        case .gas: return "Gas"
        case .food: return "Food"
        case .coffee: return "Coffee"
        case .charging: return "EV charging"
        case .parking: return "Parking"
        }
    }
    var symbol: String {
        switch self {
        case .gas: return "fuelpump.fill"
        case .food: return "fork.knife"
        case .coffee: return "cup.and.saucer.fill"
        case .charging: return "bolt.car.fill"
        case .parking: return "parkingsign"
        }
    }
    var query: String {
        switch self {
        case .gas: return "gas station"
        case .food: return "restaurant"
        case .coffee: return "coffee"
        case .charging: return "EV charging station"
        case .parking: return "parking"
        }
    }
}

/// Finds places close to the part of the route still ahead.
@MainActor
final class StopFinder: ObservableObject {
    @Published private(set) var results: [StopResult] = []
    @Published private(set) var isSearching = false

    static let maxSideDistance = 2_000.0
    static let minAhead = 300.0

    func search(_ category: StopCategory, route: Route, progress: Double) async {
        isSearching = true
        defer { isSearching = false }

        // Search around the middle of the next stretch of road, wide enough to cover it.
        let center = route.position(atOffset: progress + min(route.distance - progress, 8_000) / 2).coordinate
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            latitudinalMeters: 24_000, longitudinalMeters: 24_000
        )

        guard let response = try? await MKLocalSearch(request: request).start() else {
            results = []
            return
        }
        results = response.mapItems.compactMap { item -> StopResult? in
            let c = item.placemark.coordinate
            let near = route.nearest(to: Coordinate(latitude: c.latitude, longitude: c.longitude), after: progress)
            guard near.offset <= Self.maxSideDistance, near.along - progress >= Self.minAhead else { return nil }
            return StopResult(item: item, distanceAhead: near.along - progress, sideDistance: near.offset)
        }
        .sorted { $0.sideDistance < $1.sideDistance }
        .prefix(12)
        .map { $0 }
    }
}
