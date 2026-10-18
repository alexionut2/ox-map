import Foundation
import OxydeCore

/// Build-time configuration, read from Info.plist keys that are filled from
/// `Config/Secrets.xcconfig`. Missing values mean "not configured" and the matching
/// feature reports that state honestly instead of falling back to fake data.
struct AppConfiguration {
    /// Base URL of the Oxyde backend (traffic incidents and community reports).
    let backendBaseURL: URL?
    /// Vector engine tile source. These are client-side, domain/bundle-restricted keys
    /// meant to be embedded (e.g. MapTiler "public" keys). Never put server secrets here.
    let vectorTiles: VectorTileConfiguration?
    let premiumProductIDs: [String]

    static let current = AppConfiguration(bundle: .main)

    init(bundle: Bundle) {
        func string(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Unexpanded "$(VAR)" means the xcconfig did not define it.
            return v.isEmpty || v.hasPrefix("$(") ? nil : v
        }
        backendBaseURL = string("OXBackendBaseURL").flatMap(URL.init(string:))
        if let tiles = string("OXVectorTileJSONURL"), let glyphs = string("OXVectorGlyphsURL") {
            vectorTiles = VectorTileConfiguration(
                vectorTileJSONURL: tiles, glyphsURL: glyphs,
                fontStack: string("OXVectorFontStack").map { $0.components(separatedBy: ",") } ?? ["Noto Sans Regular"],
                imageryTileURL: string("OXVectorImageryTileURL"),
                terrainTileJSONURL: string("OXVectorTerrainTileJSONURL"),
                attribution: string("OXVectorAttribution") ?? "© OpenMapTiles © OpenStreetMap contributors")
        } else {
            vectorTiles = nil
        }
        premiumProductIDs = (string("OXPremiumProductIDs") ?? "")
            .components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Whether the MapLibre package is linked into this build.
    static var vectorEngineLinked: Bool {
        #if canImport(MapLibre)
        return true
        #else
        return false
        #endif
    }

    var vectorEngineAvailable: Bool { Self.vectorEngineLinked && vectorTiles?.isComplete == true }
}
