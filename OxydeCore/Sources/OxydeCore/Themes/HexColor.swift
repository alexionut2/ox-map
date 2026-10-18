import Foundation

/// An sRGB color stored as `#RRGGBB` or `#RRGGBBAA`. Themes keep colors as hex strings so
/// they export to readable JSON and drop straight into map style documents.
public struct HexColor: Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
                      blue: Double(value & 0xff) / 255)
        } else {
            self.init(red: Double((value >> 24) & 0xff) / 255, green: Double((value >> 16) & 0xff) / 255,
                      blue: Double((value >> 8) & 0xff) / 255, alpha: Double(value & 0xff) / 255)
        }
    }

    public init(stringLiteral value: String) {
        self = HexColor(hex: value) ?? HexColor(red: 1, green: 0, blue: 1)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let v = HexColor(hex: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid hex color \(s)")
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hexString)
    }

    static func clamp(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }

    private static func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }

    public var hexString: String {
        if alpha >= 0.999 {
            return String(format: "#%02X%02X%02X", Self.byte(red), Self.byte(green), Self.byte(blue))
        }
        return String(format: "#%02X%02X%02X%02X", Self.byte(red), Self.byte(green), Self.byte(blue), Self.byte(alpha))
    }

    /// `rgba(r, g, b, a)` for style documents that want alpha separately.
    public var cssRGBA: String {
        String(format: "rgba(%d, %d, %d, %.2f)", Self.byte(red), Self.byte(green), Self.byte(blue), alpha)
    }

    public var description: String { hexString }

    public func withAlpha(_ a: Double) -> HexColor { HexColor(red: red, green: green, blue: blue, alpha: a) }

    /// WCAG relative luminance.
    public var luminance: Double {
        func ch(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(red) + 0.7152 * ch(green) + 0.0722 * ch(blue)
    }

    /// WCAG contrast ratio between two colors, 1...21.
    public static func contrast(_ a: HexColor, _ b: HexColor) -> Double {
        let l1 = max(a.luminance, b.luminance), l2 = min(a.luminance, b.luminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }

    public func mixed(with other: HexColor, amount t: Double) -> HexColor {
        HexColor(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                 blue: blue + (other.blue - blue) * t, alpha: alpha + (other.alpha - alpha) * t)
    }
}
