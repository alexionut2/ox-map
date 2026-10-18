import Foundation

public enum DayNightMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Always use the default theme.
    case off
    /// Follow the system's light/dark appearance.
    case system
    /// Switch at local sunrise and sunset, computed from the current location.
    case sunTimes
    public var id: String { rawValue }
}

public enum SpeedometerStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case hidden, minimal, digital, ring
    public var id: String { rawValue }
}

public enum ArrivalDisplay: String, Codable, Sendable, CaseIterable, Identifiable {
    case arrivalTime, timeRemaining, both
    public var id: String { rawValue }
}

/// Interface elements the user can hide for a cleaner full-screen map.
public enum HUDElement: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case speedometer, compass, layersButton, reportButton, soundButton, studioButton, quickAccess, trafficLegend
    public var id: String { rawValue }
}

public struct VoiceSettings: Codable, Hashable, Sendable {
    /// `AVSpeechSynthesisVoice.identifier`. `nil` picks the best installed voice for the language.
    public var voiceIdentifier: String?
    /// BCP-47 language for the voice, e.g. "en-US". `nil` follows the device.
    public var language: String?
    /// 0...1, relative to the system volume.
    public var volume: Double
    /// 0.8...1.2 multiplier on the default speaking rate.
    public var rate: Double
    public var guidanceLevel: GuidanceLevel
    /// Lower other audio (music, podcasts) while an instruction plays.
    public var duckOtherAudio: Bool
    /// Pause spoken-word audio such as podcasts instead of ducking it.
    public var pauseSpokenAudio: Bool

    public init(voiceIdentifier: String? = nil, language: String? = nil, volume: Double = 1, rate: Double = 1,
                guidanceLevel: GuidanceLevel = .full, duckOtherAudio: Bool = true, pauseSpokenAudio: Bool = true) {
        self.voiceIdentifier = voiceIdentifier
        self.language = language
        self.volume = volume
        self.rate = rate
        self.guidanceLevel = guidanceLevel
        self.duckOtherAudio = duckOtherAudio
        self.pauseSpokenAudio = pauseSpokenAudio
    }
}

public enum TripPrecision: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Start and end rounded to about 100 m, no route shape.
    case approximate
    /// Exact start and end plus a simplified route shape.
    case precise
    public var id: String { rawValue }
}

/// Every user preference. Stored as JSON in UserDefaults; synced through iCloud only when
/// the user has turned sync on.
/// The marker that shows the driver's position while navigating.
public enum VehicleIcon: String, Codable, Sendable, CaseIterable, Identifiable {
    case arrow, sedan, sports, suv, motorbike, rocket, saucer, block
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .sedan: return "Sedan"
        case .sports: return "Sports Car"
        case .suv: return "SUV"
        case .motorbike: return "Motorbike"
        case .rocket: return "Rocket"
        case .saucer: return "Flying Saucer"
        case .block: return "Block Cart"
        }
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var hasCompletedOnboarding: Bool
    public var activeProfileID: String?

    // Appearance
    public var defaultThemeID: String
    public var dayThemeID: String
    public var nightThemeID: String
    public var dayNightMode: DayNightMode
    /// Overrides the theme's accent everywhere when set.
    public var accentOverride: HexColor?
    public var speedometer: SpeedometerStyle
    public var arrivalDisplay: ArrivalDisplay
    public var hapticsEnabled: Bool
    public var hiddenElements: Set<HUDElement>
    public var mapEngine: MapEngine

    // Map
    public var showsTraffic: Bool
    public var showsPOI: Bool
    public var labelDensity: LabelDensity
    public var cameraMode: CameraMode
    /// Multiplies the theme's camera distance (0.6 = closer, 1.6 = farther).
    public var zoomScale: Double

    // Navigation
    public var routePreferences: RoutePreferences
    public var units: UnitSystem
    public var voice: VoiceSettings
    public var rerouteAutomatically: Bool

    // CarPlay
    /// When `nil`, CarPlay uses the CarPlay variant of the phone's active theme.
    public var carPlayThemeID: String?

    // Community and privacy
    public var communityReportsEnabled: Bool
    public var showsPoliceReports: Bool
    public var showsSpeedCameraReports: Bool
    public var tripHistoryEnabled: Bool
    public var tripPrecision: TripPrecision
    public var cloudSyncEnabled: Bool

    // Play
    public var vehicleIcon: VehicleIcon
    /// Explorer mode: remembers explored squares on this device. Off until turned on.
    public var explorerEnabled: Bool
    /// Earn XP and achievements. Kept on the device.
    public var progressEnabled: Bool
    /// The name shown to friends in a convoy.
    public var convoyDisplayName: String

    public init() {
        hasCompletedOnboarding = false
        activeProfileID = DriverProfile.dailyDriver.id
        defaultThemeID = ThemeRegistry.defaultThemeID
        dayThemeID = ThemeRegistry.defaultDayThemeID
        nightThemeID = ThemeRegistry.defaultNightThemeID
        dayNightMode = .off
        accentOverride = nil
        speedometer = .digital
        arrivalDisplay = .both
        hapticsEnabled = true
        hiddenElements = []
        mapEngine = .vector
        showsTraffic = true
        showsPOI = true
        labelDensity = .medium
        cameraMode = .headingUp
        zoomScale = 1
        routePreferences = RoutePreferences()
        units = .automatic
        voice = VoiceSettings()
        rerouteAutomatically = true
        carPlayThemeID = nil
        communityReportsEnabled = true
        showsPoliceReports = true
        showsSpeedCameraReports = true
        tripHistoryEnabled = false
        tripPrecision = .approximate
        cloudSyncEnabled = false
        vehicleIcon = .arrow
        explorerEnabled = false
        progressEnabled = true
        convoyDisplayName = ""
    }

    /// The theme ID to render now, given the day/night state.
    public func activeThemeID(nightActive: Bool) -> String {
        switch dayNightMode {
        case .off: return defaultThemeID
        case .system, .sunTimes: return nightActive ? nightThemeID : dayThemeID
        }
    }

    /// Clamps values that may have come from an older version or another device.
    public mutating func normalize() {
        zoomScale = min(1.6, max(0.6, zoomScale))
        convoyDisplayName = String(convoyDisplayName.prefix(24))
        voice.volume = min(1, max(0, voice.volume))
        voice.rate = min(1.2, max(0.8, voice.rate))
    }
}

// Decoding tolerates missing keys so settings saved by an older version keep working.
extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding, activeProfileID, defaultThemeID, dayThemeID, nightThemeID, dayNightMode,
             accentOverride, speedometer, arrivalDisplay, hapticsEnabled, hiddenElements, mapEngine, showsTraffic,
             showsPOI, labelDensity, cameraMode, zoomScale, routePreferences, units, voice, rerouteAutomatically,
             carPlayThemeID, communityReportsEnabled, showsPoliceReports, showsSpeedCameraReports,
             tripHistoryEnabled, tripPrecision, cloudSyncEnabled, vehicleIcon, explorerEnabled, progressEnabled,
             convoyDisplayName
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ current: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? current
        }
        hasCompletedOnboarding = get(.hasCompletedOnboarding, hasCompletedOnboarding)
        activeProfileID = (try? c.decodeIfPresent(String.self, forKey: .activeProfileID)) ?? nil
        defaultThemeID = get(.defaultThemeID, defaultThemeID)
        dayThemeID = get(.dayThemeID, dayThemeID)
        nightThemeID = get(.nightThemeID, nightThemeID)
        dayNightMode = get(.dayNightMode, dayNightMode)
        accentOverride = (try? c.decodeIfPresent(HexColor.self, forKey: .accentOverride)) ?? nil
        speedometer = get(.speedometer, speedometer)
        arrivalDisplay = get(.arrivalDisplay, arrivalDisplay)
        hapticsEnabled = get(.hapticsEnabled, hapticsEnabled)
        hiddenElements = get(.hiddenElements, hiddenElements)
        mapEngine = get(.mapEngine, mapEngine)
        showsTraffic = get(.showsTraffic, showsTraffic)
        showsPOI = get(.showsPOI, showsPOI)
        labelDensity = get(.labelDensity, labelDensity)
        cameraMode = get(.cameraMode, cameraMode)
        zoomScale = get(.zoomScale, zoomScale)
        routePreferences = get(.routePreferences, routePreferences)
        units = get(.units, units)
        voice = get(.voice, voice)
        rerouteAutomatically = get(.rerouteAutomatically, rerouteAutomatically)
        carPlayThemeID = (try? c.decodeIfPresent(String.self, forKey: .carPlayThemeID)) ?? nil
        communityReportsEnabled = get(.communityReportsEnabled, communityReportsEnabled)
        showsPoliceReports = get(.showsPoliceReports, showsPoliceReports)
        showsSpeedCameraReports = get(.showsSpeedCameraReports, showsSpeedCameraReports)
        tripHistoryEnabled = get(.tripHistoryEnabled, tripHistoryEnabled)
        tripPrecision = get(.tripPrecision, tripPrecision)
        cloudSyncEnabled = get(.cloudSyncEnabled, cloudSyncEnabled)
        vehicleIcon = get(.vehicleIcon, vehicleIcon)
        explorerEnabled = get(.explorerEnabled, explorerEnabled)
        progressEnabled = get(.progressEnabled, progressEnabled)
        convoyDisplayName = get(.convoyDisplayName, convoyDisplayName)
        normalize()
    }
}
