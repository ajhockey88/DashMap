import Foundation
import MapKit

struct SavedPlace: Codable, Identifiable, Hashable {
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(name)|\(latitude)|\(longitude)" }

    init(item: MKMapItem) {
        let p = item.placemark
        name = item.name ?? "Dropped pin"
        subtitle = [p.thoroughfare, p.locality].compactMap { $0 }.joined(separator: ", ")
        latitude = p.coordinate.latitude
        longitude = p.coordinate.longitude
    }

    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = name
        return item
    }
}

/// Recent destinations plus Home and Work shortcuts, kept in UserDefaults.
@MainActor
final class PlacesStore: ObservableObject {
    @Published private(set) var recents: [SavedPlace] = []
    @Published private(set) var home: SavedPlace?
    @Published private(set) var work: SavedPlace?

    private let defaults = UserDefaults.standard

    init() {
        recents = load([SavedPlace].self, "places.recents") ?? []
        home = load(SavedPlace.self, "places.home")
        work = load(SavedPlace.self, "places.work")
    }

    func addRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        recents.insert(place, at: 0)
        recents = Array(recents.prefix(8))
        save(recents, "places.recents")
    }

    func remove(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        save(recents, "places.recents")
    }

    func setHome(_ place: SavedPlace) { home = place; save(place, "places.home") }
    func setWork(_ place: SavedPlace) { work = place; save(place, "places.work") }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
