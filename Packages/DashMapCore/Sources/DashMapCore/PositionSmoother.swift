import Foundation

/// Smooths GPS fixes with a constant-velocity Kalman filter, weighting each fix by its reported accuracy,
/// so jitter and single bad readings move the position far less than the raw coordinates would.
public struct PositionSmoother {
    private var origin: Coordinate?
    private var pos = (x: 0.0, y: 0.0)
    private var vel = (x: 0.0, y: 0.0)
    /// Position/velocity covariance, shared by both axes: [[p00, p01], [p01, p11]].
    private var p00 = 0.0, p01 = 0.0, p11 = 0.0
    private var lastTime: Date?

    /// Typical driving acceleration noise, m/s².
    static let accelerationNoise = 2.0
    /// A gap longer than this restarts the filter.
    static let maxGap: TimeInterval = 15

    public init() {}

    public mutating func reset() { self = PositionSmoother() }

    public mutating func update(_ c: Coordinate, accuracy: Double, speed: Double, course: Double?, at time: Date) -> Coordinate {
        let r = max(accuracy, 3)
        guard let origin, let last = lastTime, time.timeIntervalSince(last) <= Self.maxGap, time > last else {
            start(at: c, accuracy: r, speed: speed, course: course, time: time)
            return c
        }

        let m = Self.metersPerDegree(at: origin.latitude)
        let dt = time.timeIntervalSince(last)

        // Predict.
        pos.x += vel.x * dt
        pos.y += vel.y * dt
        let q = Self.accelerationNoise * Self.accelerationNoise
        let n00 = p00 + 2 * dt * p01 + dt * dt * p11 + q * pow(dt, 4) / 4
        let n01 = p01 + dt * p11 + q * pow(dt, 3) / 2
        let n11 = p11 + q * dt * dt
        (p00, p01, p11) = (n00, n01, n11)

        // Update with the measured position.
        let z = (x: (c.longitude - origin.longitude) * m.lon, y: (c.latitude - origin.latitude) * m.lat)
        if hypot(z.x - pos.x, z.y - pos.y) > 150 {   // a jump too large to be real: trust the new fix
            start(at: c, accuracy: r, speed: speed, course: course, time: time)
            return c
        }
        let s = p00 + r * r
        let k0 = p00 / s, k1 = p01 / s
        let inn = (x: z.x - pos.x, y: z.y - pos.y)
        pos.x += k0 * inn.x; pos.y += k0 * inn.y
        vel.x += k1 * inn.x; vel.y += k1 * inn.y
        let old01 = p01
        p11 -= k1 * old01
        p01 *= (1 - k0)
        p00 *= (1 - k0)

        // Blend in the reported velocity, which is usually better than one derived from positions.
        if let course, speed > 1 {
            let rad = course * .pi / 180
            vel.x = 0.5 * vel.x + 0.5 * speed * sin(rad)
            vel.y = 0.5 * vel.y + 0.5 * speed * cos(rad)
        }
        lastTime = time
        return Coordinate(latitude: origin.latitude + pos.y / m.lat, longitude: origin.longitude + pos.x / m.lon)
    }

    private mutating func start(at c: Coordinate, accuracy r: Double, speed: Double, course: Double?, time: Date) {
        origin = c
        pos = (0, 0)
        if let course, speed > 1 {
            let rad = course * .pi / 180
            vel = (speed * sin(rad), speed * cos(rad))
        } else {
            vel = (0, 0)
        }
        (p00, p01, p11) = (r * r, 0, 100)
        lastTime = time
    }

    private static func metersPerDegree(at latitude: Double) -> (lat: Double, lon: Double) {
        let lat = 111_320.0
        return (lat, lat * max(0.1, cos(latitude * .pi / 180)))
    }
}
