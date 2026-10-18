import Foundation

/// Sunrise and sunset times (NOAA algorithm), used for automatic day/night themes.
/// Accurate to about a minute at non-polar latitudes, which is plenty for switching a map.
public enum SolarCalculator {
    public enum Result: Equatable, Sendable {
        case normal(sunrise: Date, sunset: Date)
        case polarDay
        case polarNight
    }

    /// Official zenith (sun 0.833° below the horizon).
    static let zenith = 90.833

    public static func sunTimes(on date: Date, at c: Coordinate) -> Result {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let dayStart = cal.date(from: comps),
              let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) else { return .polarNight }

        let n = Double(dayOfYear)
        let γ = 2 * Double.pi / 365 * (n - 1 + 0.5)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(γ) - 0.032077 * sin(γ)
                               - 0.014615 * cos(2 * γ) - 0.040849 * sin(2 * γ))
        let decl = 0.006918 - 0.399912 * cos(γ) + 0.070257 * sin(γ) - 0.006758 * cos(2 * γ)
            + 0.000907 * sin(2 * γ) - 0.002697 * cos(3 * γ) + 0.00148 * sin(3 * γ)
        let lat = c.latitude * .pi / 180
        let cosH = (cos(zenith * .pi / 180) / (cos(lat) * cos(decl))) - tan(lat) * tan(decl)
        if cosH > 1 { return .polarNight }
        if cosH < -1 { return .polarDay }
        let ha = acos(cosH) * 180 / .pi
        let sunriseMinutes = 720 - 4 * (c.longitude + ha) - eqTime
        let sunsetMinutes = 720 - 4 * (c.longitude - ha) - eqTime
        return .normal(sunrise: dayStart.addingTimeInterval(sunriseMinutes * 60),
                       sunset: dayStart.addingTimeInterval(sunsetMinutes * 60))
    }

    /// Whether it is night at a place and time.
    public static func isNight(at date: Date, coordinate: Coordinate) -> Bool {
        // Times are computed per UTC day, and a local day's daylight can straddle UTC
        // midnight, so check the daylight windows of the neighboring days too.
        for offset in [-1.0, 0, 1] {
            switch sunTimes(on: date.addingTimeInterval(offset * 86_400), at: coordinate) {
            case .polarDay where offset == 0: return false
            case .polarNight where offset == 0: return true
            case let .normal(sunrise, sunset):
                if date >= sunrise && date <= sunset { return false }
            default: break
            }
        }
        return true
    }
}
