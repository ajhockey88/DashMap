import Foundation
import DashMapCore

/// Minimal client for the public Overpass API (OpenStreetMap). Asks a few public servers, staggered, and takes the first answer; failures return nil.
enum Overpass {
    static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
    ]
    /// A slow or hung server doesn't hold up the request: the next one is tried this many seconds later, in parallel.
    private static let stagger = 4.0

    static func run(_ query: String, timeout: TimeInterval = 8) async -> Data? {
        await runDetailed(query, timeout: timeout).data
    }

    /// Like `run`, but says what went wrong (last server tried) when it fails, for the on-screen diagnostics.
    static func runDetailed(_ query: String, timeout: TimeInterval = 8) async -> (data: Data?, failure: String?) {
        await withTaskGroup(of: (Data?, String?).self) { group in
            for (i, endpoint) in endpoints.enumerated() {
                group.addTask {
                    if i > 0 { try? await Task.sleep(nanoseconds: UInt64(Double(i) * stagger * 1_000_000_000)) }
                    if Task.isCancelled { return (nil, nil) }
                    return await request(endpoint, query, timeout)
                }
            }
            var failure: String?
            for await result in group {
                if let data = result.0 {
                    group.cancelAll()   // the first good answer wins
                    return (data, nil)
                }
                failure = result.1 ?? failure
            }
            return (nil, failure)
        }
    }

    private static func request(_ endpoint: String, _ query: String, _ timeout: TimeInterval) async -> (Data?, String?) {
        guard let url = URL(string: endpoint) else { return (nil, nil) }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("DashMap/1.0 (iOS navigation app)", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("data=\(encoded)".utf8)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { return (nil, "\(url.host ?? "server") answered \(code)") }
            // An overloaded server answers 200 with a "runtime error" remark instead of roads; let another server answer.
            if data.range(of: Data("runtime error".utf8)) != nil { return (nil, "\(url.host ?? "server") timed out") }
            return (data, nil)
        } catch {
            return (nil, "\(url.host ?? "server"): \(error.localizedDescription)")
        }
    }
}
