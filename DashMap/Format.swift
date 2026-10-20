import Foundation

struct Units {
    var metric: Bool

    static var localeDefault: Units { Units(metric: Locale.current.measurementSystem == .metric) }

    func distance(_ meters: Double) -> String {
        if metric {
            if meters < 1000 { return "\(Int((meters / 10).rounded() * 10)) m" }
            return String(format: "%.1f km", meters / 1000)
        }
        let feet = meters * 3.28084
        if feet < 528 { return "\(Int((feet / 50).rounded() * 50)) ft" }
        return String(format: "%.1f mi", meters / 1609.344)
    }

    /// Speed from m/s as a number plus unit label.
    func speed(_ metersPerSecond: Double) -> (value: Int, unit: String) {
        let v = max(0, metersPerSecond)
        return metric ? (Int((v * 3.6).rounded()), "km/h") : (Int((v * 2.23694).rounded()), "mph")
    }
}

func formatDuration(_ seconds: Double) -> String {
    let minutes = Int((seconds / 60).rounded())
    return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(max(1, minutes)) min"
}
