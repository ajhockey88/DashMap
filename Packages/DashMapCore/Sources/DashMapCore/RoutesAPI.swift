import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Google Routes API (v2) `computeRoutes` request building and response parsing.
public enum RoutesAPI {
    public static let endpoint = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!

    public enum Destination: Sendable {
        case coordinate(Coordinate)
        case placeId(String)
    }

    public enum Failure: Error, Equatable {
        case noRoute
        case server(String)
    }

    static let fieldMask = [
        "routes.duration",
        "routes.distanceMeters",
        "routes.polyline.encodedPolyline",
        "routes.legs.steps.distanceMeters",
        "routes.legs.steps.staticDuration",
        "routes.legs.steps.navigationInstruction",
    ].joined(separator: ",")

    public static func makeRequest(
        apiKey: String,
        origin: Coordinate,
        heading: Double? = nil,
        destination: Destination,
        languageCode: String = "en-US"
    ) throws -> URLRequest {
        var originLocation: [String: Any] = ["latLng": ["latitude": origin.latitude, "longitude": origin.longitude]]
        if let heading, heading >= 0 { originLocation["heading"] = Int(heading.rounded()) % 360 }

        let dest: [String: Any]
        switch destination {
        case .coordinate(let c):
            dest = ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]]
        case .placeId(let id):
            dest = ["placeId": id]
        }

        let body: [String: Any] = [
            "origin": ["location": originLocation],
            "destination": dest,
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
            "polylineEncoding": "ENCODED_POLYLINE",
            "languageCode": languageCode,
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func parse(_ data: Data) throws -> Route {
        let decoder = JSONDecoder()
        if let err = try? decoder.decode(ErrorEnvelope.self, from: data), let message = err.error?.message {
            throw Failure.server(message)
        }
        let response = try decoder.decode(Response.self, from: data)
        guard let r = response.routes?.first, let encoded = r.polyline?.encodedPolyline else { throw Failure.noRoute }

        let steps = (r.legs ?? []).flatMap { $0.steps ?? [] }.map { s in
            RouteStep(
                instruction: s.navigationInstruction?.instructions ?? "Continue",
                maneuver: s.navigationInstruction?.maneuver ?? .straight,
                distance: Double(s.distanceMeters ?? 0),
                duration: seconds(s.staticDuration)
            )
        }
        guard let route = Route(polyline: Geo.decodePolyline(encoded), steps: steps, duration: seconds(r.duration)) else {
            throw Failure.noRoute
        }
        return route
    }

    /// Parses protobuf durations such as "123s" or "123.5s".
    static func seconds(_ s: String?) -> Double {
        guard let s, s.hasSuffix("s") else { return 0 }
        return Double(s.dropLast()) ?? 0
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { var message: String? }
        var error: Body?
    }
    private struct Response: Decodable { var routes: [RouteDTO]? }
    private struct RouteDTO: Decodable {
        var duration: String?
        var polyline: Polyline?
        var legs: [Leg]?
    }
    private struct Polyline: Decodable { var encodedPolyline: String }
    private struct Leg: Decodable { var steps: [StepDTO]? }
    private struct StepDTO: Decodable {
        var distanceMeters: Int?
        var staticDuration: String?
        var navigationInstruction: Instruction?
    }
    private struct Instruction: Decodable {
        var maneuver: Maneuver?
        var instructions: String?
    }
}
