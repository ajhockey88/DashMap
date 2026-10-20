import Foundation
import DashMapCore

struct PlaceSuggestion: Identifiable, Hashable {
    let id: String   // Google place ID
    let title: String
}

/// Places API (New) autocomplete. Enable "Places API (New)" for your key.
enum PlacesAPI {
    static func autocomplete(_ input: String, near: Coordinate?) async throws -> [PlaceSuggestion] {
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:autocomplete")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.googleAPIKey, forHTTPHeaderField: "X-Goog-Api-Key")

        var body: [String: Any] = ["input": input]
        if let near {
            body["locationBias"] = ["circle": [
                "center": ["latitude": near.latitude, "longitude": near.longitude],
                "radius": 50_000.0,
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        struct Response: Decodable {
            struct Suggestion: Decodable {
                struct Prediction: Decodable {
                    struct Text: Decodable { let text: String }
                    let placeId: String
                    let text: Text
                }
                let placePrediction: Prediction?
            }
            let suggestions: [Suggestion]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.suggestions ?? []).compactMap {
            $0.placePrediction.map { PlaceSuggestion(id: $0.placeId, title: $0.text.text) }
        }
    }
}
