import Foundation

public struct CorridorWay: Sendable {
    public var id: Int64?
    public var tags: [String: String]
    public var points: [Coordinate]
    let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double

    public init(id: Int64? = nil, tags: [String: String], points: [Coordinate]) {
        self.id = id
        self.tags = tags
        self.points = points
        minLat = points.map(\.latitude).min() ?? 0
        maxLat = points.map(\.latitude).max() ?? 0
        minLon = points.map(\.longitude).min() ?? 0
        maxLon = points.map(\.longitude).max() ?? 0
    }

    /// Cheap rejection test: is `p` farther than `meters` outside this way's bounding box?
    func isFar(from p: Coordinate, meters: Double) -> Bool {
        let dLat = meters / 111_320
        let dLon = dLat / max(0.1, cos(p.latitude * .pi / 180))
        return p.latitude < minLat - dLat || p.latitude > maxLat + dLat
            || p.longitude < minLon - dLon || p.longitude > maxLon + dLon
    }
}

public struct CorridorNode: Sendable {
    public var id: Int64?
    public var coordinate: Coordinate
    public var tags: [String: String]
}

/// The OpenStreetMap roads and highway exits along a route, downloaded once in a few large pieces
/// instead of one request per turn.
public struct Corridor: Sendable {
    public private(set) var ways: [CorridorWay] = []
    public private(set) var nodes: [CorridorNode] = []
    private var wayIDs = Set<Int64>()
    private var nodeIDs = Set<Int64>()

    public init() {}

    public init(ways: [CorridorWay], nodes: [CorridorNode]) {
        for way in ways { add(way) }
        for node in nodes { add(node) }
    }

    public mutating func merge(_ other: Corridor) {
        for way in other.ways { add(way) }
        for node in other.nodes { add(node) }
    }

    private mutating func add(_ way: CorridorWay) {
        if let id = way.id, !wayIDs.insert(id).inserted { return }
        ways.append(way)
    }

    private mutating func add(_ node: CorridorNode) {
        if let id = node.id, !nodeIDs.insert(id).inserted { return }
        nodes.append(node)
    }
}

public enum OSMCorridor {
    static let roadFilter = "[highway~\"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|service|living_street|road|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$\"]"

    /// Overpass QL for roads and exit junctions along the stretch of `route` between two offsets (meters).
    /// Uses a chain of small bounding boxes: that is served from the spatial index and answers in a second or two,
    /// where an `around` search over a long polyline makes the public servers time out in dense cities.
    public static func query(for route: Route, from start: Double, to end: Double, spacing: Double = 100, margin: Double = 30, samplesPerBox: Int = 3) -> String {
        var points: [Coordinate] = []
        var d = max(0, start)
        let limit = min(end, route.distance)
        while d < limit {
            points.append(route.position(atOffset: d).coordinate)
            d += spacing
        }
        points.append(route.position(atOffset: limit).coordinate)

        var statements: [String] = []
        var i = 0
        while i < points.count - 1 || (i == 0 && points.count == 1) {
            let window = points[i..<min(points.count, i + samplesPerBox + 1)]
            let lats = window.map(\.latitude), lons = window.map(\.longitude)
            let dLat = margin / 111_320
            let dLon = dLat / max(0.1, cos((lats.reduce(0, +) / Double(lats.count)) * .pi / 180))
            let box = String(format: "%.5f,%.5f,%.5f,%.5f", lats.min()! - dLat, lons.min()! - dLon, lats.max()! + dLat, lons.max()! + dLon)
            statements.append("way\(roadFilter)(\(box));node[highway=motorway_junction](\(box));")
            i += samplesPerBox
        }
        return "[out:json][timeout:25];(\(statements.joined()));out tags geom;"
    }

    public static func parse(_ data: Data) -> Corridor? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        // An overloaded Overpass server answers 200 with a "runtime error" remark and no (or partial) roads; that is a failure.
        if let remark = response.remark, remark.contains("runtime error") || remark.contains("timed out") { return nil }
        var ways: [CorridorWay] = []
        var nodes: [CorridorNode] = []
        for element in response.elements {
            let tags = element.tags ?? [:]
            if element.type == "way", let geometry = element.geometry, geometry.count >= 2 {
                ways.append(CorridorWay(id: element.id, tags: tags, points: geometry.map { Coordinate(latitude: $0.lat, longitude: $0.lon) }))
            } else if element.type == "node", let lat = element.lat, let lon = element.lon {
                nodes.append(CorridorNode(id: element.id, coordinate: Coordinate(latitude: lat, longitude: lon), tags: tags))
            }
        }
        return Corridor(ways: ways, nodes: nodes)
    }

    private struct Response: Decodable { var elements: [Element]; var remark: String? }
    private struct Element: Decodable {
        var type: String
        var id: Int64?
        var lat: Double?
        var lon: Double?
        var tags: [String: String]?
        var geometry: [Point]?
    }
    private struct Point: Decodable { var lat: Double; var lon: Double }
}
