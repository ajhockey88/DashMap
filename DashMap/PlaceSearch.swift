import MapKit
import Combine

/// Wraps MKLocalSearchCompleter for destination autocomplete.
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String, near: CLLocationCoordinate2D?) {
        if let near {
            completer.region = MKCoordinateRegion(center: near, latitudinalMeters: 100_000, longitudinalMeters: 100_000)
        }
        completer.queryFragment = query
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> MKMapItem? {
        try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
