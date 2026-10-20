import Foundation

/// What the road under the car is called and how fast it may be driven.
public struct RoadInfo: Equatable, Sendable {
    public var name: String?
    /// Route number such as "I 95" or "US 1" (first one when several are listed).
    public var ref: String?
    public var speedLimitKph: Double?
    /// Motorway or trunk road.
    public var isHighway: Bool

    /// What to show as the road's name: its street name, else its route number.
    public var title: String? { name ?? ref }
}

/// Road name, route number and speed limit from OpenStreetMap tags (Overpass).
public enum OSMRoad {
    static let drivable: Set<String> = [
        "motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential",
        "service", "living_street", "road",
        "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link",
    ]

    public static func query(near point: Coordinate) -> String {
        let at = String(format: "%.6f,%.6f", point.latitude, point.longitude)
        return "[out:json][timeout:8];way(around:15,\(at))[highway];out tags geom;"
    }

    public static func info(from data: Data, at point: Coordinate, travelBearing: Double) -> RoadInfo? {
        guard let match = OSMWays.nearest(in: data, at: point, travelBearing: travelBearing, maxOffset: 15, accepting: { tags, _, _ in
            tags["highway"].map(drivable.contains) ?? false
        }) else { return nil }

        let tags = match.tags
        let name = tags["name"]
        let ref = tags["ref"]?.split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        guard name != nil || ref != nil else { return nil }

        let limit = parseSpeed(tags[match.alongWay ? "maxspeed:forward" : "maxspeed:backward"] ?? tags["maxspeed"])
        let highway = tags["highway"] ?? ""
        return RoadInfo(name: name, ref: ref, speedLimitKph: limit, isHighway: highway.hasPrefix("motorway") || highway.hasPrefix("trunk"))
    }

    /// "50" → 50 km/h, "30 mph" → 48.3 km/h; "none", "signals" and other words → nil.
    static func parseSpeed(_ value: String?) -> Double? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasSuffix("mph") {
            return Double(text.dropLast(3).trimmingCharacters(in: .whitespaces)).map { $0 * 1.609344 }
        }
        return Double(text)
    }
}
