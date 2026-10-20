import Foundation
import DashMapCore

/// Minimal client for the public Overpass API (OpenStreetMap). One small query per request; failures return nil.
enum Overpass {
    static func run(_ query: String) async -> Data? {
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("DashMap/1.0 (iOS navigation app)", forHTTPHeaderField: "User-Agent")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        request.httpBody = Data("data=\(encoded)".utf8)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

enum LaneService {
    static func fetch(near point: Coordinate, bearing: Double, maneuver: Maneuver) async -> LaneGuidance? {
        guard let data = await Overpass.run(OSMLanes.query(near: point)) else { return nil }
        return OSMLanes.guidance(from: data, at: point, travelBearing: bearing, maneuver: maneuver)
    }
}

enum RoadService {
    static func fetch(near point: Coordinate, bearing: Double) async -> RoadInfo? {
        guard let data = await Overpass.run(OSMRoad.query(near: point)) else { return nil }
        return OSMRoad.info(from: data, at: point, travelBearing: bearing)
    }
}
