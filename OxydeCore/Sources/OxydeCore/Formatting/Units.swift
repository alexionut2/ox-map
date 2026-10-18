import Foundation

public enum UnitSystem: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic, metric, imperial
    public var id: String { rawValue }

    /// Resolves `.automatic` from a region code. The US, Liberia and Myanmar use miles,
    /// and so does the UK for road distances.
    public func resolved(regionCode: String?) -> UnitSystem {
        guard self == .automatic else { return self }
        switch regionCode?.uppercased() {
        case "US", "LR", "MM", "GB", "UK": return .imperial
        default: return .metric
        }
    }
}

/// A distance rounded the way a driver wants to hear it, in display and spoken forms.
public struct GuidanceDistance: Equatable, Sendable {
    public var value: String
    public var unit: String
    public var spoken: String
    public var display: String { "\(value) \(unit)" }
}

public enum DistanceFormatter {
    /// Rounds distances to steps that are easy to read at a glance: 10 m below 100 m,
    /// 50 m below 1 km, then 0.1 km; 50 ft below 1000 ft, then 0.1 mi.
    public static func guidance(meters: Double, system: UnitSystem) -> GuidanceDistance {
        let m = max(0, meters)
        switch system {
        case .imperial:
            let feet = m * 3.28084
            let miles = m / 1609.344
            if feet < 1000 {
                let rounded = feet < 100 ? max(10, (feet / 10).rounded() * 10) : (feet / 50).rounded() * 50
                let v = Int(rounded)
                return GuidanceDistance(value: "\(v)", unit: "ft", spoken: "\(v) feet")
            }
            if miles < 10 {
                let tenth = (miles * 10).rounded() / 10
                let s = formatDecimal(tenth)
                let spoken: String
                if tenth == 0.5 { spoken = "half a mile" }
                else if tenth == 1 { spoken = "1 mile" }
                else { spoken = "\(s) miles" }
                return GuidanceDistance(value: s, unit: "mi", spoken: spoken)
            }
            let v = Int(miles.rounded())
            return GuidanceDistance(value: "\(v)", unit: "mi", spoken: "\(v) miles")
        case .metric, .automatic:
            if m < 1000 {
                let rounded = m < 100 ? max(10, (m / 10).rounded() * 10) : (m / 50).rounded() * 50
                if rounded >= 1000 {
                    return GuidanceDistance(value: "1", unit: "km", spoken: "1 kilometer")
                }
                let v = Int(rounded)
                return GuidanceDistance(value: "\(v)", unit: "m", spoken: "\(v) meters")
            }
            let km = m / 1000
            if km < 10 {
                let tenth = (km * 10).rounded() / 10
                let s = formatDecimal(tenth)
                return GuidanceDistance(value: s, unit: "km", spoken: tenth == 1 ? "1 kilometer" : "\(s) kilometers")
            }
            let v = Int(km.rounded())
            return GuidanceDistance(value: "\(v)", unit: "km", spoken: "\(v) kilometers")
        }
    }

    static func formatDecimal(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.1f", v)
    }
}

public enum SpeedFormatter {
    /// Converts m/s to the unit used for the speedometer.
    public static func value(metersPerSecond: Double, system: UnitSystem) -> Int {
        let factor = system == .imperial ? 2.236936 : 3.6
        return Int((max(0, metersPerSecond) * factor).rounded())
    }

    public static func unitLabel(_ system: UnitSystem) -> String {
        system == .imperial ? "mph" : "km/h"
    }
}

public enum DurationFormatter {
    /// "1 h 05 min", "12 min", "< 1 min".
    public static func short(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        if total < 60 { return "< 1 min" }
        let minutes = (total + 30) / 60
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : String(format: "%d h %02d min", h, m)
    }

    /// Signed delta used in route comparisons: "+4 min", "same time".
    public static func delta(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes == 0 { return "same time" }
        return minutes > 0 ? "+\(minutes) min" : "−\(-minutes) min"
    }
}
