import Foundation
import DashMapCore

/// Downloads the OpenStreetMap roads along the route in large pieces, a little ahead of the car, and keeps them.
/// Lanes, road names, speed limits and exit signs are then looked up locally, with no request per turn.
@MainActor
final class CorridorStore {
    private(set) var corridor = Corridor()
    private var loadedUpTo = 0.0
    private var task: Task<Void, Never>?
    private var retryAfter = Date.distantPast
    private var generation = 0
    /// Why the last download failed, if it did (shown in the simulated-drive diagnostics).
    private(set) var lastFailure: String?
    private var startedAt: Date?

    var summary: String {
        let km = Int(loadedUpTo / 1000)
        let laneRoads = corridor.ways.filter { $0.tags.keys.contains { $0.hasPrefix("turn:lanes") } }.count
        var text = "Map data: \(km) km, \(corridor.ways.count) roads, \(laneRoads) with lane tags."
        if task != nil, let startedAt { text += " Downloading for \(Int(Date().timeIntervalSince(startedAt))) s." }
        if let lastFailure { text += " Last download failed: \(lastFailure)." }
        return text
    }

    static let chunk = 3_000.0        // meters of route per request (small enough for busy cities not to time out)
    static let firstChunk = 1_000.0   // the first request is smaller so it finishes fast
    static let lookahead = 8_000.0    // stay at least this far ahead of the car

    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        corridor = Corridor()
        loadedUpTo = 0
        retryAfter = .distantPast
        lastFailure = nil
    }

    /// True once the data for the route up to `offset` has been downloaded.
    func covers(_ offset: Double, of route: Route) -> Bool {
        loadedUpTo >= min(offset, route.distance)
    }

    func ensure(route: Route, progress: Double) {
        guard task == nil, Date() >= retryAfter else { return }
        let target = min(route.distance, progress + Self.lookahead)
        guard loadedUpTo < target else { return }

        let from = loadedUpTo
        // A small first piece so the first turns get lanes quickly; later pieces are larger.
        let to = min(route.distance, from + (from == 0 ? Self.firstChunk : Self.chunk))
        let gen = generation
        startedAt = Date()
        task = Task {
            let query = OSMCorridor.query(for: route, from: from, to: to)
            let result = await Overpass.runDetailed(query, timeout: 18)
            guard gen == generation else { return }   // the route changed while downloading
            task = nil
            guard let data = result.data, let part = OSMCorridor.parse(data) else {
                lastFailure = result.failure ?? "server was overloaded"
                retryAfter = Date().addingTimeInterval(3)
                return
            }
            lastFailure = nil
            corridor.merge(part)
            loadedUpTo = to
        }
    }
}
