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

    static let chunk = 15_000.0       // meters of route per request
    static let lookahead = 10_000.0   // stay at least this far ahead of the car

    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        corridor = Corridor()
        loadedUpTo = 0
        retryAfter = .distantPast
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
        let to = min(route.distance, from + Self.chunk)
        let gen = generation
        task = Task {
            let query = OSMCorridor.query(for: route, from: from, to: to)
            let data = await Overpass.run(query, timeout: 30)
            guard gen == generation else { return }   // the route changed while downloading
            task = nil
            guard let data, let part = OSMCorridor.parse(data) else {
                retryAfter = Date().addingTimeInterval(15)
                return
            }
            corridor.merge(part)
            loadedUpTo = to
        }
    }
}
