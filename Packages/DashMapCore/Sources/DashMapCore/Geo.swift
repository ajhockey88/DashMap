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

    /// Initial bearing from `a` to `b` in degrees clockwise from north (0..<360).
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Signed heading change from `before` to `after`, in -180...180 (positive = right).
    public static func turnAngle(before: Double, after: Double) -> Double {
        var d = (after - before).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d < -180 { d += 360 }
        return d
    }
}
