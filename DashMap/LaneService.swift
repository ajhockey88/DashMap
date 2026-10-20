import Foundation
import DashMapCore

/// Fetches lane markings for the road you're approaching a turn on from OpenStreetMap (Overpass API).
/// Best effort: any failure, or a road without lane tags, just means no lane display.
enum LaneService {
    static func fetch(near point: Coordinate, bearing: Double, maneuver: Maneuver) async -> LaneGuidance? {
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("DashMap/1.0 (iOS navigation app)", forHTTPHeaderField: "User-Agent")
        let query = OSMLanes.query(near: point).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        request.httpBody = Data("data=\(query)".utf8)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return OSMLanes.guidance(from: data, at: point, travelBearing: bearing, maneuver: maneuver)
    }
}
