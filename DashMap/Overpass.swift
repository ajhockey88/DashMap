import Foundation
import DashMapCore

/// Minimal client for the public Overpass API (OpenStreetMap). Tries a few public servers in turn; failures return nil.
enum Overpass {
    static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
    ]

    static func run(_ query: String, timeout: TimeInterval = 8) async -> Data? {
        await runDetailed(query, timeout: timeout).data
    }

    /// Like `run`, but says what went wrong (last server tried) when it fails, for the on-screen diagnostics.
    static func runDetailed(_ query: String, timeout: TimeInterval = 8) async -> (data: Data?, failure: String?) {
        var failure: String?
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("DashMap/1.0 (iOS navigation app)", forHTTPHeaderField: "User-Agent")
            request.httpBody = Data("data=\(encoded)".utf8)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200 { return (data, nil) }
                failure = "\(url.host ?? "server") answered \(code)"
            } catch {
                failure = "\(url.host ?? "server"): \(error.localizedDescription)"
            }
            if Task.isCancelled { return (nil, failure) }
        }
        return (nil, failure)
    }
}
