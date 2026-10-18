import Foundation

public enum ThemeCodecError: Error, Equatable, LocalizedError {
    case notAThemeFile
    case unsupportedVersion(Int)
    case invalidLink
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .notAThemeFile: return "This file is not an Oxyde Map theme."
        case .unsupportedVersion(let v): return "This theme was made with a newer version of Oxyde Map (format \(v))."
        case .invalidLink: return "This theme link is incomplete or damaged."
        case .tooLarge: return "This theme file is too large to be a theme."
        }
    }
}

/// Exports and imports themes as `.oxydetheme` JSON files and `oxydemap://theme` links.
public enum ThemeCodec {
    public static let fileExtension = "oxydetheme"
    public static let uniformTypeIdentifier = "com.oxydemap.theme"
    public static let linkScheme = "oxydemap"
    static let maxBytes = 64 * 1024

    struct Envelope: Codable {
        var format: String
        var theme: MapTheme
    }

    static let formatTag = "oxyde-map-theme"

    public static func exportData(_ theme: MapTheme, pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(Envelope(format: formatTag, theme: theme))
    }

    /// Decodes a theme from a file and makes it safe to keep: it gets a fresh custom ID
    /// (so an import can never overwrite a built-in or an existing theme), its numbers are
    /// clamped to the ranges the editor allows and its name is trimmed.
    public static func importData(_ data: Data) throws -> MapTheme {
        guard data.count <= maxBytes else { throw ThemeCodecError.tooLarge }
        struct VersionProbe: Decodable {
            struct T: Decodable { var schemaVersion: Int }
            var format: String?
            var theme: T?
        }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data),
              probe.format == formatTag, let version = probe.theme?.schemaVersion else {
            throw ThemeCodecError.notAThemeFile
        }
        guard version <= MapTheme.schemaVersion else { throw ThemeCodecError.unsupportedVersion(version) }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ThemeCodecError.notAThemeFile
        }
        return sanitized(envelope.theme)
    }

    public static func sanitized(_ input: MapTheme) -> MapTheme {
        var t = input
        t.id = "custom-" + UUID().uuidString.lowercased()
        t.family = .custom
        t.isPremium = false
        t.schemaVersion = MapTheme.schemaVersion
        let trimmed = t.name.trimmingCharacters(in: .whitespacesAndNewlines)
        t.name = String((trimmed.isEmpty ? "Imported Theme" : trimmed).prefix(40))
        t.summary = String(t.summary.prefix(160))
        t.route = clamp(t.route)
        t.nightRoute = t.nightRoute.map(clamp)
        t.camera.pitch = min(75, max(0, t.camera.pitch))
        t.camera.distance = min(3000, max(150, t.camera.distance))
        t.palette = clamp(t.palette)
        t.nightPalette = t.nightPalette.map(clamp)
        t.carPlay.routeWidth = min(14, max(4, t.carPlay.routeWidth))
        return t
    }

    static func clamp(_ r: RouteStyle) -> RouteStyle {
        var r = r
        r.width = min(16, max(2, r.width))
        r.casingWidth = min(6, max(0, r.casingWidth))
        r.glow = min(1, max(0, r.glow))
        return r
    }

    static func clamp(_ p: VectorPalette) -> VectorPalette {
        var p = p
        p.roadWidthScale = min(2, max(0.5, p.roadWidthScale))
        p.labelSizeScale = min(1.6, max(0.7, p.labelSizeScale))
        p.roadGlow = min(1, max(0, p.roadGlow))
        return p
    }

    // MARK: Links

    /// `oxydemap://theme?v=1&d=<base64url JSON>`
    public static func shareLink(for theme: MapTheme) throws -> URL {
        let data = try exportData(theme, pretty: false)
        var c = URLComponents()
        c.scheme = linkScheme
        c.host = "theme"
        c.queryItems = [URLQueryItem(name: "v", value: String(MapTheme.schemaVersion)),
                        URLQueryItem(name: "d", value: base64URLEncode(data))]
        guard let url = c.url else { throw ThemeCodecError.invalidLink }
        return url
    }

    public static func theme(fromLink url: URL) throws -> MapTheme {
        guard url.scheme == linkScheme, url.host == "theme",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let payload = items.first(where: { $0.name == "d" })?.value,
              let data = base64URLDecode(payload) else {
            throw ThemeCodecError.invalidLink
        }
        return try importData(data)
    }

    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func base64URLDecode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        return Data(base64Encoded: b)
    }
}
