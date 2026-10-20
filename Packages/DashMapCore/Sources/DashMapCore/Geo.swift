import Foundation

public struct Coordinate: Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum Geo {
    static let earthRadius = 6_371_000.0

    /// Great-circle distance in meters.
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Projects `p` onto segment `a`-`b` in a local flat approximation.
    /// Returns the fraction along the segment (0...1) and the distance in meters from `p` to that point.
    public static func project(_ p: Coordinate, onto a: Coordinate, _ b: Coordinate) -> (t: Double, offset: Double) {
        let mPerDeg = earthRadius * .pi / 180
        let cosLat = cos(a.latitude * .pi / 180)
        func local(_ c: Coordinate) -> (x: Double, y: Double) {
            ((c.longitude - a.longitude) * cosLat * mPerDeg, (c.latitude - a.latitude) * mPerDeg)
        }
        let pp = local(p)
        let bb = local(b)
        let len2 = bb.x * bb.x + bb.y * bb.y
        let t = len2 == 0 ? 0 : max(0, min(1, (pp.x * bb.x + pp.y * bb.y) / len2))
        return (t, hypot(pp.x - t * bb.x, pp.y - t * bb.y))
    }

    /// Decodes a Google encoded polyline (precision 5).
    public static func decodePolyline(_ encoded: String) -> [Coordinate] {
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lon = 0
        var result: [Coordinate] = []

        func nextValue() -> Int? {
            var shift = 0
            var value = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                value |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (value & 1) != 0 ? ~(value >> 1) : value >> 1 }
            }
            return nil
        }

        while index < bytes.count {
            guard let dLat = nextValue(), let dLon = nextValue() else { break }
            lat += dLat
            lon += dLon
            result.append(Coordinate(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return result
    }
}
