import Foundation

public enum ThemeFamily: String, Codable, Sendable, CaseIterable, Identifiable {
    case essential, automotive, futuristic, gaming, artistic, custom
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .essential: return "Essential"
        case .automotive: return "Premium Automotive"
        case .futuristic: return "Futuristic"
        case .gaming: return "Game Worlds"
        case .artistic: return "Artistic"
        case .custom: return "My Themes"
        }
    }
}

/// The imagery underneath the map.
public enum BaseMap: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Vector street map.
    case standard
    /// Satellite imagery without labels.
    case satellite
    /// Satellite imagery with roads and labels.
    case hybrid
    public var id: String { rawValue }
}

public enum MapAppearance: String, Codable, Sendable, CaseIterable, Identifiable {
    case light, dark
    /// Follows the app's day/night setting.
    case automatic
    public var id: String { rawValue }
}

public enum MapEmphasis: String, Codable, Sendable, CaseIterable, Identifiable {
    case standard, muted
    public var id: String { rawValue }
}

public enum MapElevation: String, Codable, Sendable, CaseIterable, Identifiable {
    case flat
    /// 3D terrain and buildings where the provider has them.
    case realistic
    public var id: String { rawValue }
}

public enum POIVisibility: String, Codable, Sendable, CaseIterable, Identifiable {
    case all
    /// Only places a driver needs: fuel, charging, parking, food, restrooms, hospitals.
    case driving
    case none
    public var id: String { rawValue }
}

public enum LabelDensity: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, low, medium, high
    public var id: String { rawValue }
}

public enum CameraMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case northUp, headingUp, perspective3D
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .northUp: return "North up"
        case .headingUp: return "Heading up"
        case .perspective3D: return "3D perspective"
        }
    }
}

public enum PanelStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Translucent material panels.
    case glass
    /// Opaque graphite panels with higher contrast.
    case solid
    public var id: String { rawValue }
}

public enum TypographyStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// SF Pro, the iOS default.
    case standard
    /// SF Pro Rounded for a softer look.
    case rounded
    /// Monospaced digits and wide tracking, instrument-cluster style.
    case technical
    /// Heavy condensed weights for a sporty look.
    case sport
    public var id: String { rawValue }
}

public enum ManeuverPanelStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case standard
    /// Larger arrow and distance, like an instrument cluster.
    case cockpit
    public var id: String { rawValue }
}

/// How the route line is drawn. Applied by every renderer, since the route is an
/// overlay Oxyde Map draws itself.
public struct RouteStyle: Codable, Hashable, Sendable {
    public var color: HexColor
    public var alternateColor: HexColor
    public var traveledColor: HexColor
    public var width: Double
    public var casingColor: HexColor
    public var casingWidth: Double
    /// 0 = no glow, 1 = strongest glow.
    public var glow: Double
    public var glowColor: HexColor

    public init(color: HexColor, alternateColor: HexColor, traveledColor: HexColor, width: Double,
                casingColor: HexColor, casingWidth: Double, glow: Double, glowColor: HexColor) {
        self.color = color
        self.alternateColor = alternateColor
        self.traveledColor = traveledColor
        self.width = width
        self.casingColor = casingColor
        self.casingWidth = casingWidth
        self.glow = glow
        self.glowColor = glowColor
    }
}

public struct CameraStyle: Codable, Hashable, Sendable {
    public var mode: CameraMode
    /// Camera tilt in degrees while navigating. 0 is straight down.
    public var pitch: Double
    /// Camera distance from the vehicle in meters while navigating at city speeds.
    public var distance: Double

    public init(mode: CameraMode, pitch: Double, distance: Double) {
        self.mode = mode
        self.pitch = pitch
        self.distance = distance
    }
}

/// How road ends and corners are drawn by the vector engine.
public enum RoadShape: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Rounded ends and joins, like most navigation maps.
    case smooth
    /// Square ends and sharp corners, for blocky and pixel-art looks.
    case blocky
    public var id: String { rawValue }
}

/// Colors and sizes for the full vector renderer. Apple's MapKit does not expose road,
/// land or water colors, so these apply only when the vector engine is active; the app
/// labels every such control accordingly.
public struct VectorPalette: Codable, Hashable, Sendable {
    public var background: HexColor
    public var land: HexColor
    public var park: HexColor
    public var water: HexColor
    public var roadHighway: HexColor
    public var roadMajor: HexColor
    public var roadMinor: HexColor
    public var roadCasing: HexColor
    public var building: HexColor
    public var buildingExtrusion: HexColor
    public var label: HexColor
    public var labelHalo: HexColor
    public var roadWidthScale: Double
    public var labelSizeScale: Double
    public var labelDensity: LabelDensity
    public var trafficFree: HexColor
    public var trafficModerate: HexColor
    public var trafficHeavy: HexColor
    public var trafficClosed: HexColor
    /// Rounded or blocky road geometry.
    public var roadShape: RoadShape
    /// 0 = none, 1 = strong neon glow around highways and main roads.
    public var roadGlow: Double
    public var boldLabels: Bool
    public var uppercaseLabels: Bool
    /// Rounds building heights up to whole blocks (8 m) for a voxel look.
    public var blockBuildings: Bool

    public init(background: HexColor, land: HexColor, park: HexColor, water: HexColor, roadHighway: HexColor,
                roadMajor: HexColor, roadMinor: HexColor, roadCasing: HexColor, building: HexColor,
                buildingExtrusion: HexColor, label: HexColor, labelHalo: HexColor, roadWidthScale: Double = 1,
                labelSizeScale: Double = 1, labelDensity: LabelDensity = .medium,
                trafficFree: HexColor = "#2ECC71", trafficModerate: HexColor = "#F5B700",
                trafficHeavy: HexColor = "#FF5A36", trafficClosed: HexColor = "#B3002D",
                roadShape: RoadShape = .smooth, roadGlow: Double = 0, boldLabels: Bool = false,
                uppercaseLabels: Bool = false, blockBuildings: Bool = false) {
        self.background = background
        self.land = land
        self.park = park
        self.water = water
        self.roadHighway = roadHighway
        self.roadMajor = roadMajor
        self.roadMinor = roadMinor
        self.roadCasing = roadCasing
        self.building = building
        self.buildingExtrusion = buildingExtrusion
        self.label = label
        self.labelHalo = labelHalo
        self.roadWidthScale = roadWidthScale
        self.labelSizeScale = labelSizeScale
        self.labelDensity = labelDensity
        self.trafficFree = trafficFree
        self.trafficModerate = trafficModerate
        self.trafficHeavy = trafficHeavy
        self.trafficClosed = trafficClosed
        self.roadShape = roadShape
        self.roadGlow = roadGlow
        self.boldLabels = boldLabels
        self.uppercaseLabels = uppercaseLabels
        self.blockBuildings = blockBuildings
    }

    private enum CodingKeys: String, CodingKey {
        case background, land, park, water, roadHighway, roadMajor, roadMinor, roadCasing, building
        case buildingExtrusion, label, labelHalo, roadWidthScale, labelSizeScale, labelDensity
        case trafficFree, trafficModerate, trafficHeavy, trafficClosed
        case roadShape, roadGlow, boldLabels, uppercaseLabels, blockBuildings
    }

    /// Themes saved or shared before the style extras existed still open; missing extras
    /// fall back to the classic look.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decode(HexColor.self, forKey: .background)
        land = try c.decode(HexColor.self, forKey: .land)
        park = try c.decode(HexColor.self, forKey: .park)
        water = try c.decode(HexColor.self, forKey: .water)
        roadHighway = try c.decode(HexColor.self, forKey: .roadHighway)
        roadMajor = try c.decode(HexColor.self, forKey: .roadMajor)
        roadMinor = try c.decode(HexColor.self, forKey: .roadMinor)
        roadCasing = try c.decode(HexColor.self, forKey: .roadCasing)
        building = try c.decode(HexColor.self, forKey: .building)
        buildingExtrusion = try c.decode(HexColor.self, forKey: .buildingExtrusion)
        label = try c.decode(HexColor.self, forKey: .label)
        labelHalo = try c.decode(HexColor.self, forKey: .labelHalo)
        roadWidthScale = try c.decode(Double.self, forKey: .roadWidthScale)
        labelSizeScale = try c.decode(Double.self, forKey: .labelSizeScale)
        labelDensity = try c.decode(LabelDensity.self, forKey: .labelDensity)
        trafficFree = try c.decode(HexColor.self, forKey: .trafficFree)
        trafficModerate = try c.decode(HexColor.self, forKey: .trafficModerate)
        trafficHeavy = try c.decode(HexColor.self, forKey: .trafficHeavy)
        trafficClosed = try c.decode(HexColor.self, forKey: .trafficClosed)
        roadShape = try c.decodeIfPresent(RoadShape.self, forKey: .roadShape) ?? .smooth
        roadGlow = try c.decodeIfPresent(Double.self, forKey: .roadGlow) ?? 0
        boldLabels = try c.decodeIfPresent(Bool.self, forKey: .boldLabels) ?? false
        uppercaseLabels = try c.decodeIfPresent(Bool.self, forKey: .uppercaseLabels) ?? false
        blockBuildings = try c.decodeIfPresent(Bool.self, forKey: .blockBuildings) ?? false
    }
}

public struct InterfaceStyle: Codable, Hashable, Sendable {
    public var accent: HexColor
    public var panel: PanelStyle
    public var typography: TypographyStyle
    public var maneuverPanel: ManeuverPanelStyle

    public init(accent: HexColor, panel: PanelStyle, typography: TypographyStyle, maneuverPanel: ManeuverPanelStyle) {
        self.accent = accent
        self.panel = panel
        self.typography = typography
        self.maneuverPanel = maneuverPanel
    }
}

/// Simplified settings for the car display, which must stay high-contrast and calm.
public struct CarPlayVariant: Codable, Hashable, Sendable {
    public var routeColor: HexColor
    public var routeWidth: Double
    /// CarPlay follows the car's own light/dark appearance unless this forces dark.
    public var alwaysDark: Bool
    public var showsTraffic: Bool

    public init(routeColor: HexColor, routeWidth: Double, alwaysDark: Bool, showsTraffic: Bool) {
        self.routeColor = routeColor
        self.routeWidth = routeWidth
        self.alwaysDark = alwaysDark
        self.showsTraffic = showsTraffic
    }
}

/// A complete navigation look: base map configuration, route styling, camera, vector
/// palette, interface accents and a CarPlay variant.
public struct MapTheme: Codable, Hashable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var summary: String
    public var family: ThemeFamily
    public var isPremium: Bool
    /// Built-in theme this one was copied from, for "restore defaults".
    public var basedOn: String?

    public var baseMap: BaseMap
    public var appearance: MapAppearance
    public var emphasis: MapEmphasis
    public var elevation: MapElevation
    public var showsBuildings: Bool
    public var poiVisibility: POIVisibility
    public var showsTraffic: Bool
    /// Terrain shading in the vector engine (needs a terrain tile source).
    public var showsHillshade: Bool

    public var route: RouteStyle
    public var camera: CameraStyle
    public var palette: VectorPalette
    /// Palette used at night when the theme's appearance is automatic.
    public var nightPalette: VectorPalette?
    public var nightRoute: RouteStyle?
    public var interface: InterfaceStyle
    public var carPlay: CarPlayVariant

    public init(id: String, name: String, summary: String, family: ThemeFamily, isPremium: Bool = false,
                basedOn: String? = nil, baseMap: BaseMap, appearance: MapAppearance, emphasis: MapEmphasis,
                elevation: MapElevation, showsBuildings: Bool, poiVisibility: POIVisibility, showsTraffic: Bool,
                showsHillshade: Bool = false, route: RouteStyle, camera: CameraStyle, palette: VectorPalette,
                nightPalette: VectorPalette? = nil, nightRoute: RouteStyle? = nil, interface: InterfaceStyle,
                carPlay: CarPlayVariant) {
        self.schemaVersion = Self.schemaVersion
        self.id = id
        self.name = name
        self.summary = summary
        self.family = family
        self.isPremium = isPremium
        self.basedOn = basedOn
        self.baseMap = baseMap
        self.appearance = appearance
        self.emphasis = emphasis
        self.elevation = elevation
        self.showsBuildings = showsBuildings
        self.poiVisibility = poiVisibility
        self.showsTraffic = showsTraffic
        self.showsHillshade = showsHillshade
        self.route = route
        self.camera = camera
        self.palette = palette
        self.nightPalette = nightPalette
        self.nightRoute = nightRoute
        self.interface = interface
        self.carPlay = carPlay
    }

    /// Whether the map should render dark, given the app's current day/night state.
    public func isDark(nightActive: Bool) -> Bool {
        switch appearance {
        case .light: return false
        case .dark: return true
        case .automatic: return nightActive
        }
    }

    public func resolvedPalette(nightActive: Bool) -> VectorPalette {
        if appearance == .automatic, nightActive, let night = nightPalette { return night }
        return palette
    }

    public func resolvedRoute(nightActive: Bool) -> RouteStyle {
        if appearance == .automatic, nightActive, let night = nightRoute { return night }
        return route
    }

    /// A user-editable copy with a new identity.
    public func duplicated(named newName: String, id newID: String = "custom-" + UUID().uuidString.lowercased()) -> MapTheme {
        var copy = self
        copy.id = newID
        copy.name = newName
        copy.family = .custom
        copy.isPremium = false
        copy.basedOn = family == .custom ? basedOn : id
        return copy
    }
}
