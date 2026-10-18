import Foundation

/// Every feature's real state, shown on the Diagnostics screen and mirrored in
/// docs/STATUS.md. Nothing here is a marketing list: a feature is `.implemented` only
/// when the code path exists and runs against a real service.
public enum FeatureState: String, Sendable, Equatable {
    case implemented
    /// Code is in place but needs a key, backend, entitlement or account.
    case requiresConfiguration
    /// The chosen provider does not supply the data.
    case providerLimited
    case planned
}

public struct FeatureStatus: Sendable, Identifiable, Equatable {
    public var id: String
    public var area: String
    public var name: String
    public var state: FeatureState
    public var note: String

    public init(id: String, area: String, name: String, state: FeatureState, note: String) {
        self.id = id
        self.area = area
        self.name = name
        self.state = state
        self.note = note
    }
}

public enum FeatureCatalog {
    public struct Environment: Sendable {
        public var backendConfigured: Bool
        public var vectorEngineAvailable: Bool
        public var storeConfigured: Bool
        public init(backendConfigured: Bool, vectorEngineAvailable: Bool, storeConfigured: Bool) {
            self.backendConfigured = backendConfigured
            self.vectorEngineAvailable = vectorEngineAvailable
            self.storeConfigured = storeConfigured
        }
    }

    public static func features(_ env: Environment) -> [FeatureStatus] {
        func cfg(_ ok: Bool) -> FeatureState { ok ? .implemented : .requiresConfiguration }
        return [
            FeatureStatus(id: "map", area: "Map", name: "Apple Maps rendering, 2D/3D, satellite, hybrid", state: .implemented, note: "MapKit"),
            FeatureStatus(id: "themes", area: "Map Studio", name: "15 built-in themes, live switching", state: .implemented,
                          note: "Base map, appearance, emphasis, elevation, POI, traffic, route, camera and UI apply on Apple Maps."),
            FeatureStatus(id: "vector", area: "Map Studio", name: "Custom road, land, water, building and label colors",
                          state: cfg(env.vectorEngineAvailable),
                          note: "Needs the MapLibre package and a vector tile source (docs/PROVIDERS.md)."),
            FeatureStatus(id: "theme-share", area: "Map Studio", name: "Theme export, import and share links", state: .implemented, note: ".oxydetheme files and oxydemap:// links"),
            FeatureStatus(id: "search", area: "Search", name: "Address, place, category and coordinate search with autocomplete", state: .implemented, note: "MapKit"),
            FeatureStatus(id: "along-route", area: "Search", name: "Search along the route", state: .implemented, note: "MapKit searches at points ahead on the route"),
            FeatureStatus(id: "place-hours", area: "Search", name: "Opening hours and ratings", state: .providerLimited, note: "Not exposed by MapKit; shown only if a provider supplies them."),
            FeatureStatus(id: "ev-filters", area: "Search", name: "EV connector and power filters", state: .providerLimited, note: "MapKit finds chargers but not connector data."),
            FeatureStatus(id: "routing", area: "Navigation", name: "Driving routes, alternatives, multi-stop, avoid tolls/highways", state: .implemented, note: "MKDirections"),
            FeatureStatus(id: "ferries", area: "Navigation", name: "Avoid ferries", state: .providerLimited, note: "MKDirections has no ferry preference."),
            FeatureStatus(id: "guidance", area: "Navigation", name: "Turn-by-turn, spoken guidance, rerouting, ETA refresh", state: .implemented, note: "Provider instructions, AVSpeechSynthesizer"),
            FeatureStatus(id: "lanes", area: "Navigation", name: "Lane guidance", state: .providerLimited, note: "MapKit steps carry no lane data. Model and UI are ready for a provider that does."),
            FeatureStatus(id: "speed-limits", area: "Navigation", name: "Speed limits", state: .providerLimited, note: "Not provided by MapKit. The speedometer shows your speed only."),
            FeatureStatus(id: "traffic-layer", area: "Traffic", name: "Live traffic on the map and traffic-aware ETAs", state: .implemented, note: "Apple Maps traffic"),
            FeatureStatus(id: "incidents", area: "Traffic", name: "Accidents, closures and roadworks from a traffic provider",
                          state: cfg(env.backendConfigured), note: "Oxyde backend with a TomTom Traffic key"),
            FeatureStatus(id: "reports", area: "Community", name: "Submit, confirm and dismiss driver reports",
                          state: cfg(env.backendConfigured), note: "Oxyde backend"),
            FeatureStatus(id: "carplay", area: "CarPlay", name: "Map, guidance, trip previews, search, favorites, reports", state: .requiresConfiguration,
                          note: "Works in the CarPlay Simulator; devices need Apple's CarPlay navigation entitlement."),
            FeatureStatus(id: "profiles", area: "Personalization", name: "Settings, driver profiles, day/night switching", state: .implemented, note: ""),
            FeatureStatus(id: "sync", area: "Personalization", name: "iCloud settings sync", state: .requiresConfiguration, note: "Needs the iCloud key-value entitlement and user opt-in."),
            FeatureStatus(id: "trips", area: "Trips", name: "Opt-in trip history and dashboard", state: .implemented, note: "Stored on device with SwiftData"),
            FeatureStatus(id: "premium", area: "Premium", name: "Premium themes via StoreKit", state: cfg(env.storeConfigured), note: "Products must exist in App Store Connect."),
            FeatureStatus(id: "offline", area: "Offline", name: "Downloaded offline maps", state: .providerLimited, note: "MapKit has no offline download API; tiles are only cached."),
            FeatureStatus(id: "dashboard", area: "CarPlay", name: "CarPlay Dashboard and instrument cluster", state: .planned, note: ""),
        ]
    }
}
