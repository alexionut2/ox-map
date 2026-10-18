import Foundation

/// The built-in Oxyde Map themes. Each theme is real configuration: base map type,
/// appearance, emphasis, elevation, POI filter and traffic are applied by MapKit; route,
/// camera and interface styling are drawn by Oxyde Map; the vector palette is compiled
/// into a MapLibre style document when the vector engine is enabled.
public enum ThemeRegistry {
    public static let defaultThemeID = "oxyde.dark"
    public static let defaultNightThemeID = "oxyde.nightdrive"
    public static let defaultDayThemeID = "oxyde.classic"

    public static var all: [MapTheme] { builtIns }

    public static func theme(id: String) -> MapTheme? { builtIns.first { $0.id == id } }

    public static func themes(in family: ThemeFamily) -> [MapTheme] { builtIns.filter { $0.family == family } }

    // MARK: Palettes

    static let lightBase = VectorPalette(
        background: "#F2F1EE", land: "#F2F1EE", park: "#D7EBCF", water: "#A9CDEB",
        roadHighway: "#FFD27A", roadMajor: "#FFFFFF", roadMinor: "#FFFFFF", roadCasing: "#C9C6BF",
        building: "#E2DFDA", buildingExtrusion: "#D6D2CB", label: "#2E3238", labelHalo: "#FFFFFF",
        roadWidthScale: 1, labelSizeScale: 1, labelDensity: .medium)

    static let graphite = VectorPalette(
        background: "#121418", land: "#15181C", park: "#17221B", water: "#0B1A26",
        roadHighway: "#3A4049", roadMajor: "#2C3138", roadMinor: "#22262C", roadCasing: "#0B0D10",
        building: "#1C2026", buildingExtrusion: "#262B33", label: "#9BA3AE", labelHalo: "#0B0D10",
        roadWidthScale: 1, labelSizeScale: 1, labelDensity: .medium)

    static let deepBlack = VectorPalette(
        background: "#000000", land: "#030405", park: "#05090A", water: "#02070C",
        roadHighway: "#24282E", roadMajor: "#1A1D22", roadMinor: "#121418", roadCasing: "#000000",
        building: "#0A0B0D", buildingExtrusion: "#111317", label: "#7E8792", labelHalo: "#000000",
        roadWidthScale: 1, labelSizeScale: 1.1, labelDensity: .low)

    static func route(_ color: HexColor, width: Double = 7, glow: Double = 0, glowColor: HexColor? = nil,
                      casing: HexColor = "#0B0D10", casingWidth: Double = 2,
                      alternate: HexColor = "#7C8591", traveled: HexColor = "#5A616B") -> RouteStyle {
        RouteStyle(color: color, alternateColor: alternate, traveledColor: traveled, width: width,
                   casingColor: casing, casingWidth: casingWidth, glow: glow, glowColor: glowColor ?? color)
    }

    static func ui(_ accent: HexColor, panel: PanelStyle = .glass, type: TypographyStyle = .standard,
                   maneuver: ManeuverPanelStyle = .standard) -> InterfaceStyle {
        InterfaceStyle(accent: accent, panel: panel, typography: type, maneuverPanel: maneuver)
    }

    static func car(_ color: HexColor, width: Double = 9, dark: Bool = false, traffic: Bool = true) -> CarPlayVariant {
        CarPlayVariant(routeColor: color, routeWidth: width, alwaysDark: dark, showsTraffic: traffic)
    }

    // MARK: Built-ins

    static let builtIns: [MapTheme] = [
        // Essential
        MapTheme(id: "oxyde.classic", name: "Oxyde Classic",
                 summary: "Clean streets, readable labels, clear routes and live traffic colors.",
                 family: .essential, baseMap: .standard, appearance: .automatic, emphasis: .standard,
                 elevation: .flat, showsBuildings: true, poiVisibility: .all, showsTraffic: true,
                 route: route("#1E88FF", width: 7, casing: "#0B4FA8"),
                 camera: CameraStyle(mode: .headingUp, pitch: 35, distance: 700),
                 palette: lightBase, nightPalette: graphite,
                 nightRoute: route("#3DA0FF", width: 7, glow: 0.2, casing: "#082A57"),
                 interface: ui("#1E88FF"), carPlay: car("#1E88FF")),

        MapTheme(id: "oxyde.dark", name: "Oxyde Dark",
                 summary: "Dark roads, subtle labels and a glowing route.",
                 family: .essential, baseMap: .standard, appearance: .dark, emphasis: .standard,
                 elevation: .flat, showsBuildings: true, poiVisibility: .all, showsTraffic: true,
                 route: route("#2F9BFF", width: 7, glow: 0.45, casing: "#061B33"),
                 camera: CameraStyle(mode: .headingUp, pitch: 40, distance: 700),
                 palette: graphite, interface: ui("#2F9BFF"), carPlay: car("#2F9BFF", dark: true)),

        MapTheme(id: "oxyde.satellite", name: "Oxyde Satellite",
                 summary: "Satellite imagery with street names and navigation overlays.",
                 family: .essential, baseMap: .hybrid, appearance: .dark, emphasis: .standard,
                 elevation: .flat, showsBuildings: true, poiVisibility: .driving, showsTraffic: true,
                 route: route("#00E5FF", width: 7, glow: 0.35, casing: "#002A33"),
                 camera: CameraStyle(mode: .headingUp, pitch: 30, distance: 800),
                 palette: graphite, interface: ui("#00E5FF"), carPlay: car("#00E5FF")),

        MapTheme(id: "oxyde.terrain", name: "Oxyde Terrain",
                 summary: "Elevation, hills and terrain features with the road network on top.",
                 family: .essential, baseMap: .standard, appearance: .light, emphasis: .standard,
                 elevation: .realistic, showsBuildings: true, poiVisibility: .driving, showsTraffic: false,
                 showsHillshade: true,
                 route: route("#E8590C", width: 7, casing: "#7A2E06"),
                 camera: CameraStyle(mode: .perspective3D, pitch: 55, distance: 900),
                 palette: VectorPalette(background: "#EDE8DC", land: "#EDE8DC", park: "#C9DDB4", water: "#9EC3DB",
                                        roadHighway: "#F2B266", roadMajor: "#FFFFFF", roadMinor: "#F8F5EE",
                                        roadCasing: "#B8AE9C", building: "#DDD5C6", buildingExtrusion: "#CFC5B3",
                                        label: "#3D3A33", labelHalo: "#F6F2E8"),
                 interface: ui("#E8590C"), carPlay: car("#E8590C")),

        MapTheme(id: "oxyde.minimal", name: "Oxyde Minimal",
                 summary: "Minimal labels, thin roads and almost no visual distractions.",
                 family: .essential, baseMap: .standard, appearance: .automatic, emphasis: .muted,
                 elevation: .flat, showsBuildings: false, poiVisibility: .none, showsTraffic: false,
                 route: route("#1C1F24", width: 5, casing: "#F5F5F5", casingWidth: 1.5,
                              alternate: "#9AA0A8", traveled: "#C4C8CD"),
                 camera: CameraStyle(mode: .headingUp, pitch: 0, distance: 650),
                 palette: VectorPalette(background: "#F5F5F5", land: "#F5F5F5", park: "#ECEFEC", water: "#DDE5EC",
                                        roadHighway: "#D0D0D0", roadMajor: "#E2E2E2", roadMinor: "#EBEBEB",
                                        roadCasing: "#F5F5F5", building: "#EFEFEF", buildingExtrusion: "#E6E6E6",
                                        label: "#8A8A8A", labelHalo: "#F5F5F5", roadWidthScale: 0.7,
                                        labelSizeScale: 0.9, labelDensity: .low),
                 nightPalette: VectorPalette(background: "#0E0F11", land: "#0E0F11", park: "#101311", water: "#0B0E12",
                                             roadHighway: "#2A2D31", roadMajor: "#202226", roadMinor: "#1A1C1F",
                                             roadCasing: "#0E0F11", building: "#131417", buildingExtrusion: "#17191C",
                                             label: "#5E636A", labelHalo: "#0E0F11", roadWidthScale: 0.7,
                                             labelSizeScale: 0.9, labelDensity: .low),
                 nightRoute: route("#FFFFFF", width: 5, casing: "#000000", casingWidth: 1.5),
                 interface: ui("#FFFFFF", panel: .solid), carPlay: car("#FFFFFF", width: 8)),

        MapTheme(id: "oxyde.nightdrive", name: "Oxyde Night Drive",
                 summary: "Deep black surroundings, muted detail and bright route guidance for night driving.",
                 family: .essential, baseMap: .standard, appearance: .dark, emphasis: .muted,
                 elevation: .flat, showsBuildings: false, poiVisibility: .driving, showsTraffic: true,
                 route: route("#00D9FF", width: 8, glow: 0.6, casing: "#000000", casingWidth: 2.5,
                              alternate: "#3B4450", traveled: "#2A3038"),
                 camera: CameraStyle(mode: .headingUp, pitch: 45, distance: 750),
                 palette: deepBlack, interface: ui("#00D9FF", panel: .solid),
                 carPlay: car("#00D9FF", width: 10, dark: true)),

        MapTheme(id: "oxyde.3d", name: "Oxyde 3D",
                 summary: "3D buildings, terrain and a low perspective camera for city driving.",
                 family: .essential, baseMap: .standard, appearance: .automatic, emphasis: .standard,
                 elevation: .realistic, showsBuildings: true, poiVisibility: .all, showsTraffic: true,
                 route: route("#4C8DFF", width: 8, glow: 0.3, casing: "#11306B"),
                 camera: CameraStyle(mode: .perspective3D, pitch: 65, distance: 450),
                 palette: lightBase, nightPalette: graphite, interface: ui("#4C8DFF"), carPlay: car("#4C8DFF")),

        // Premium automotive
        MapTheme(id: "oxyde.automotive", name: "Oxyde Automotive",
                 summary: "Graphite roads, gray buildings, restrained highlights and a prominent route.",
                 family: .automotive, baseMap: .standard, appearance: .dark, emphasis: .muted,
                 elevation: .realistic, showsBuildings: true, poiVisibility: .driving, showsTraffic: true,
                 route: route("#3D9BFF", width: 9, glow: 0.25, casing: "#0A1220", casingWidth: 2.5),
                 camera: CameraStyle(mode: .perspective3D, pitch: 50, distance: 700),
                 palette: VectorPalette(background: "#16181B", land: "#16181B", park: "#181D1A", water: "#101820",
                                        roadHighway: "#4A4F57", roadMajor: "#3A3E45", roadMinor: "#2B2E33",
                                        roadCasing: "#101114", building: "#2A2D31", buildingExtrusion: "#34383E",
                                        label: "#A6ADB6", labelHalo: "#101114", roadWidthScale: 1.1),
                 interface: ui("#3D9BFF", panel: .solid, type: .technical), carPlay: car("#3D9BFF", dark: true)),

        // Originally requested as "BMW Inspired". Shipped under an original name: using a
        // car maker's trademark in an App Store app needs that company's permission.
        MapTheme(id: "oxyde.executive", name: "Oxyde Executive",
                 summary: "Deep charcoal, understated roads, refined type and cool-blue route guidance.",
                 family: .automotive, isPremium: true, baseMap: .standard, appearance: .dark, emphasis: .muted,
                 elevation: .realistic, showsBuildings: true, poiVisibility: .driving, showsTraffic: true,
                 route: route("#4FA3FF", width: 8, glow: 0.35, glowColor: "#7FC1FF", casing: "#0C1B30",
                              alternate: "#4E5866", traveled: "#38404A"),
                 camera: CameraStyle(mode: .perspective3D, pitch: 55, distance: 650),
                 palette: VectorPalette(background: "#1A1C1F", land: "#1A1C1F", park: "#1B201E", water: "#141C26",
                                        roadHighway: "#3F4650", roadMajor: "#33383F", roadMinor: "#272A2F",
                                        roadCasing: "#121316", building: "#24272B", buildingExtrusion: "#2E3238",
                                        label: "#B7C3D0", labelHalo: "#121316", roadWidthScale: 0.95,
                                        labelSizeScale: 0.95, labelDensity: .low),
                 interface: ui("#4FA3FF", panel: .glass, type: .technical), carPlay: car("#4FA3FF", dark: true)),

        MapTheme(id: "oxyde.cockpit", name: "Oxyde Cockpit",
                 summary: "Instrument-cluster layout: big maneuvers, speed up front, simplified roads.",
                 family: .automotive, baseMap: .standard, appearance: .dark, emphasis: .muted,
                 elevation: .flat, showsBuildings: false, poiVisibility: .none, showsTraffic: true,
                 route: route("#FF6A00", width: 10, glow: 0.3, casing: "#2B1200", casingWidth: 2.5,
                              alternate: "#555B63", traveled: "#33373D"),
                 camera: CameraStyle(mode: .perspective3D, pitch: 60, distance: 550),
                 palette: VectorPalette(background: "#0C0D0F", land: "#0C0D0F", park: "#0E100F", water: "#0A0E12",
                                        roadHighway: "#30343A", roadMajor: "#25282D", roadMinor: "#1B1D21",
                                        roadCasing: "#0C0D0F", building: "#121417", buildingExtrusion: "#16181C",
                                        label: "#8D949D", labelHalo: "#0C0D0F", roadWidthScale: 0.85,
                                        labelSizeScale: 1.1, labelDensity: .low),
                 interface: ui("#FF6A00", panel: .solid, type: .technical, maneuver: .cockpit),
                 carPlay: car("#FF6A00", width: 10, dark: true)),

        MapTheme(id: "oxyde.luxury", name: "Oxyde Luxury",
                 summary: "Dark materials, restrained gold accents and a quiet visual hierarchy.",
                 family: .automotive, isPremium: true, baseMap: .standard, appearance: .dark, emphasis: .muted,
                 elevation: .realistic, showsBuildings: true, poiVisibility: .driving, showsTraffic: true,
                 route: route("#D4AF6A", width: 7, glow: 0.3, glowColor: "#F0D9A8", casing: "#2A2112",
                              alternate: "#5C5648", traveled: "#3E3A31"),
                 camera: CameraStyle(mode: .perspective3D, pitch: 50, distance: 700),
                 palette: VectorPalette(background: "#141312", land: "#141312", park: "#171815", water: "#11161B",
                                        roadHighway: "#3B3730", roadMajor: "#2E2B26", roadMinor: "#23211E",
                                        roadCasing: "#0F0E0D", building: "#211F1C", buildingExtrusion: "#2B2824",
                                        label: "#C9BFA9", labelHalo: "#0F0E0D", labelSizeScale: 0.95,
                                        labelDensity: .low),
                 interface: ui("#D4AF6A", panel: .glass, type: .standard), carPlay: car("#D4AF6A", dark: true)),

        // Futuristic
        MapTheme(id: "oxyde.neon", name: "Oxyde Neon",
                 summary: "Dark streets with luminous cyan, purple and electric-blue route lines.",
                 family: .futuristic, baseMap: .standard, appearance: .dark, emphasis: .muted,
                 elevation: .flat, showsBuildings: true, poiVisibility: .driving, showsTraffic: true,
                 route: route("#00F0FF", width: 7, glow: 0.9, glowColor: "#8A5CFF", casing: "#1A0640",
                              alternate: "#6B3FD6", traveled: "#2A2F45"),
                 camera: CameraStyle(mode: .headingUp, pitch: 45, distance: 700),
                 palette: VectorPalette(background: "#07060D", land: "#07060D", park: "#0A0C12", water: "#060B1C",
                                        roadHighway: "#2B1F5C", roadMajor: "#1D1A3A", roadMinor: "#141228",
                                        roadCasing: "#07060D", building: "#100E1E", buildingExtrusion: "#18142E",
                                        label: "#8F86C9", labelHalo: "#07060D", trafficFree: "#00F0A8",
                                        trafficModerate: "#FFC400", trafficHeavy: "#FF2E88", trafficClosed: "#FF0040"),
                 interface: ui("#00F0FF"), carPlay: car("#00F0FF", dark: true)),

        MapTheme(id: "oxyde.cyber", name: "Oxyde Cyber",
                 summary: "High-tech grid accents, sharp geometry and acid-lime highlights.",
                 family: .futuristic, isPremium: true, baseMap: .standard, appearance: .dark, emphasis: .muted,
                 elevation: .realistic, showsBuildings: true, poiVisibility: .driving, showsTraffic: true,
                 route: route("#B6FF00", width: 6, glow: 0.7, casing: "#1C2600", casingWidth: 1.5,
                              alternate: "#00B3B3", traveled: "#26302A"),
                 camera: CameraStyle(mode: .perspective3D, pitch: 60, distance: 600),
                 palette: VectorPalette(background: "#050807", land: "#050807", park: "#07100A", water: "#03100F",
                                        roadHighway: "#123A33", roadMajor: "#0E2A26", roadMinor: "#0A1C1A",
                                        roadCasing: "#00FFC6", building: "#08120F", buildingExtrusion: "#0D201B",
                                        label: "#5CF2C8", labelHalo: "#050807", roadWidthScale: 0.9,
                                        labelSizeScale: 0.95),
                 interface: ui("#B6FF00", panel: .solid, type: .technical), carPlay: car("#B6FF00", dark: true)),

        MapTheme(id: "oxyde.synthwave", name: "Oxyde Synthwave",
                 summary: "Purple and magenta tones with a retro-futuristic glow.",
                 family: .futuristic, isPremium: true, baseMap: .standard, appearance: .dark, emphasis: .muted,
                 elevation: .flat, showsBuildings: true, poiVisibility: .driving, showsTraffic: true,
                 route: route("#FF2BD6", width: 7, glow: 0.85, glowColor: "#FF8A3D", casing: "#2A0631",
                              alternate: "#7A3FD1", traveled: "#3A2448"),
                 camera: CameraStyle(mode: .perspective3D, pitch: 55, distance: 700),
                 palette: VectorPalette(background: "#120720", land: "#120720", park: "#160B26", water: "#0B0A2E",
                                        roadHighway: "#5B1F78", roadMajor: "#3E1756", roadMinor: "#2A1040",
                                        roadCasing: "#120720", building: "#1C0C30", buildingExtrusion: "#2A1246",
                                        label: "#E3A3FF", labelHalo: "#120720", trafficFree: "#3DF5C9",
                                        trafficModerate: "#FFB13D", trafficHeavy: "#FF3D6E", trafficClosed: "#FF0033"),
                 interface: ui("#FF2BD6"), carPlay: car("#FF2BD6", dark: true)),

        MapTheme(id: "oxyde.performance", name: "Oxyde Performance",
                 summary: "Bold route emphasis, strong contrast and sporty typography.",
                 family: .futuristic, baseMap: .standard, appearance: .dark, emphasis: .muted,
                 elevation: .flat, showsBuildings: false, poiVisibility: .driving, showsTraffic: true,
                 route: route("#FF1E2D", width: 10, glow: 0.4, casing: "#FFFFFF", casingWidth: 2,
                              alternate: "#6D737B", traveled: "#3A3E44"),
                 camera: CameraStyle(mode: .headingUp, pitch: 40, distance: 750),
                 palette: VectorPalette(background: "#0D0D0E", land: "#0D0D0E", park: "#101211", water: "#0B0F14",
                                        roadHighway: "#45484D", roadMajor: "#33363A", roadMinor: "#232528",
                                        roadCasing: "#0D0D0E", building: "#17181A", buildingExtrusion: "#1E2023",
                                        label: "#C4C7CC", labelHalo: "#0D0D0E", roadWidthScale: 1.15,
                                        labelSizeScale: 1.05, labelDensity: .low),
                 interface: ui("#FF1E2D", panel: .solid, type: .sport), carPlay: car("#FF1E2D", width: 10, dark: true)),
    ]
}
