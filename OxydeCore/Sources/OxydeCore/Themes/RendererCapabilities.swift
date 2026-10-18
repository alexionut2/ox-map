import Foundation

/// The map engines Oxyde Map can draw with.
public enum MapEngine: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Apple MapKit: the default. Free, no keys, works in CarPlay.
    case appleMaps
    /// MapLibre Native with a vector tile source: full control over every map color.
    /// Uses free OpenFreeMap tiles unless the build configures another provider.
    case vector
    public var id: String { rawValue }
    public var title: String { self == .appleMaps ? "Apple Maps engine" : "Vector engine" }
}

/// Theme properties, grouped the way the Studio editor presents them.
public enum ThemeProperty: String, CaseIterable, Sendable {
    case baseMap, appearance, emphasis, elevation, buildings3D, poiVisibility, traffic, hillshade
    case routeColor, routeWidth, routeGlow, routeCasing, alternateRouteColor
    case cameraMode, cameraPitch, cameraDistance
    case backgroundColor, landColor, waterColor, parkColor, roadColors, roadWidth, buildingColors
    case roadShape, roadGlow, labelStyle
    case labelVisibility, labelDensity, labelSize, labelColors
    case trafficColors, nightPalette
    case accent, panelStyle, typography, maneuverPanel
}

public enum PropertySupport: Equatable, Sendable {
    case supported
    /// Works, but only partly; the note says how.
    case partial(String)
    case unsupported(String)

    public var isUsable: Bool {
        if case .unsupported = self { return false }
        return true
    }
}

/// What each engine can actually render. The Studio uses this to badge and disable
/// controls instead of pretending a setting took effect.
public enum RendererCapabilities {
    public static func support(_ property: ThemeProperty, on engine: MapEngine) -> PropertySupport {
        switch engine {
        case .vector:
            switch property {
            case .traffic:
                return .partial("Traffic lines need a traffic tile source on your backend; incidents still show.")
            case .hillshade:
                return .partial("Needs a terrain (raster-dem) source in the provider configuration.")
            case .baseMap:
                return .partial("Satellite and hybrid need an imagery source in the provider configuration.")
            default:
                return .supported
            }
        case .appleMaps:
            switch property {
            case .baseMap, .appearance, .emphasis, .elevation, .poiVisibility, .traffic, .buildings3D:
                return .supported
            case .hillshade:
                return .partial("Apple Maps shows terrain relief through Realistic elevation in supported regions.")
            case .routeColor, .routeWidth, .routeGlow, .routeCasing, .alternateRouteColor:
                return .supported
            case .cameraMode, .cameraPitch, .cameraDistance:
                return .supported
            case .accent, .panelStyle, .typography, .maneuverPanel:
                return .supported
            case .labelVisibility:
                return .partial("Apple Maps hides labels only on Satellite; Standard and Hybrid always show them.")
            case .backgroundColor, .landColor, .waterColor, .parkColor, .roadColors, .roadWidth, .buildingColors,
                 .roadShape, .roadGlow, .labelStyle,
                 .labelDensity, .labelSize, .labelColors, .trafficColors, .nightPalette:
                return .unsupported("Apple Maps does not allow custom map colors or sizes. Switch to the vector engine.")
            }
        }
    }
}
