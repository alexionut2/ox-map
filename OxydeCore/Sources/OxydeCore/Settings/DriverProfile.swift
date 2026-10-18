import Foundation

/// A preset that changes both how the map looks and how navigation behaves. Applying a
/// profile writes its values into `AppSettings`; the user can still change anything after.
public struct DriverProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var symbol: String
    public var isBuiltIn: Bool

    public var dayThemeID: String
    public var nightThemeID: String
    public var dayNightMode: DayNightMode
    public var accentOverride: HexColor?
    public var cameraMode: CameraMode
    public var zoomScale: Double
    public var guidanceLevel: GuidanceLevel
    public var speedometer: SpeedometerStyle
    public var arrivalDisplay: ArrivalDisplay
    public var labelDensity: LabelDensity
    public var showsPOI: Bool
    public var showsTraffic: Bool
    public var hiddenElements: Set<HUDElement>
    public var routePreferences: RoutePreferences

    public init(id: String, name: String, summary: String, symbol: String, isBuiltIn: Bool = true,
                dayThemeID: String, nightThemeID: String, dayNightMode: DayNightMode = .system,
                accentOverride: HexColor? = nil, cameraMode: CameraMode, zoomScale: Double = 1,
                guidanceLevel: GuidanceLevel = .full, speedometer: SpeedometerStyle = .digital,
                arrivalDisplay: ArrivalDisplay = .both, labelDensity: LabelDensity = .medium,
                showsPOI: Bool = true, showsTraffic: Bool = true, hiddenElements: Set<HUDElement> = [],
                routePreferences: RoutePreferences = RoutePreferences()) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.isBuiltIn = isBuiltIn
        self.dayThemeID = dayThemeID
        self.nightThemeID = nightThemeID
        self.dayNightMode = dayNightMode
        self.accentOverride = accentOverride
        self.cameraMode = cameraMode
        self.zoomScale = zoomScale
        self.guidanceLevel = guidanceLevel
        self.speedometer = speedometer
        self.arrivalDisplay = arrivalDisplay
        self.labelDensity = labelDensity
        self.showsPOI = showsPOI
        self.showsTraffic = showsTraffic
        self.hiddenElements = hiddenElements
        self.routePreferences = routePreferences
    }

    public func apply(to settings: inout AppSettings) {
        settings.activeProfileID = id
        settings.dayThemeID = dayThemeID
        settings.nightThemeID = nightThemeID
        settings.defaultThemeID = dayThemeID
        settings.dayNightMode = dayNightMode
        settings.accentOverride = accentOverride
        settings.cameraMode = cameraMode
        settings.zoomScale = zoomScale
        settings.voice.guidanceLevel = guidanceLevel
        settings.speedometer = speedometer
        settings.arrivalDisplay = arrivalDisplay
        settings.labelDensity = labelDensity
        settings.showsPOI = showsPOI
        settings.showsTraffic = showsTraffic
        settings.hiddenElements = hiddenElements
        settings.routePreferences = routePreferences
        settings.normalize()
    }

    /// Captures the current settings as a new user profile.
    public static func capture(from s: AppSettings, name: String) -> DriverProfile {
        DriverProfile(id: "profile-" + UUID().uuidString.lowercased(), name: name,
                      summary: "Saved from your current settings.", symbol: "person.crop.circle", isBuiltIn: false,
                      dayThemeID: s.dayThemeID, nightThemeID: s.nightThemeID, dayNightMode: s.dayNightMode,
                      accentOverride: s.accentOverride, cameraMode: s.cameraMode, zoomScale: s.zoomScale,
                      guidanceLevel: s.voice.guidanceLevel, speedometer: s.speedometer,
                      arrivalDisplay: s.arrivalDisplay, labelDensity: s.labelDensity, showsPOI: s.showsPOI,
                      showsTraffic: s.showsTraffic, hiddenElements: s.hiddenElements,
                      routePreferences: s.routePreferences)
    }

    public static let dailyDriver = DriverProfile(
        id: "profile.daily", name: "Daily Driver",
        summary: "The Oxyde Signature look, full guidance and live traffic.",
        symbol: "car.fill", dayThemeID: "oxyde.signature", nightThemeID: "oxyde.signature", dayNightMode: .off,
        cameraMode: .headingUp)

    public static let nightDriver = DriverProfile(
        id: "profile.night", name: "Night Driver",
        summary: "Deep-black map, bright route and fewer distractions after dark.",
        symbol: "moon.stars.fill", dayThemeID: "oxyde.nightdrive", nightThemeID: "oxyde.nightdrive",
        dayNightMode: .off, cameraMode: .headingUp, labelDensity: .low, showsPOI: false,
        hiddenElements: [.trafficLegend, .studioButton])

    public static let performance = DriverProfile(
        id: "profile.performance", name: "Performance",
        summary: "Bold route emphasis and a ring speedometer for spirited, lawful driving.",
        symbol: "gauge.with.dots.needle.67percent", dayThemeID: "oxyde.performance", nightThemeID: "oxyde.performance",
        dayNightMode: .off, cameraMode: .perspective3D, zoomScale: 1.1, speedometer: .ring, labelDensity: .low)

    public static let minimal = DriverProfile(
        id: "profile.minimal", name: "Minimal",
        summary: "Only the route and the next turn. Alerts-only voice.",
        symbol: "circle.dashed", dayThemeID: "oxyde.minimal", nightThemeID: "oxyde.minimal",
        cameraMode: .headingUp, guidanceLevel: .alertsOnly, speedometer: .minimal, arrivalDisplay: .arrivalTime,
        labelDensity: .low, showsPOI: false, showsTraffic: false,
        hiddenElements: [.layersButton, .reportButton, .studioButton, .trafficLegend, .compass])

    public static let touring = DriverProfile(
        id: "profile.touring", name: "Touring",
        summary: "Terrain and 3D views, more places on the map and a wider camera for long trips.",
        symbol: "mountain.2.fill", dayThemeID: "oxyde.terrain", nightThemeID: "oxyde.automotive",
        cameraMode: .perspective3D, zoomScale: 1.3, labelDensity: .high, showsPOI: true,
        routePreferences: RoutePreferences(avoidTolls: false, avoidHighways: false))

    public static let gameMode = DriverProfile(
        id: "profile.game", name: "Game Mode",
        summary: "Open-world minimap style, top-down camera and bold labels.",
        symbol: "gamecontroller.fill", dayThemeID: "oxyde.openworld", nightThemeID: "oxyde.openworld",
        dayNightMode: .off, cameraMode: .headingUp, zoomScale: 0.9, labelDensity: .low)

    public static let builtIns: [DriverProfile] = [dailyDriver, nightDriver, performance, minimal, touring, gameMode]
}
