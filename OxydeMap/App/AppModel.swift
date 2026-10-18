import SwiftUI
import Observation
import OxydeCore

/// The app's composition root. One instance is shared by the phone UI and the CarPlay
/// scene so both always show the same route, theme and settings.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let configuration: AppConfiguration
    let settings: SettingsStore
    let themes: ThemeStore
    let location: LocationManager
    let reachability: Reachability
    let persistence: PersistenceController
    let routing: RoutingService
    let search: MapKitSearchService
    let voice: VoiceGuidanceManager
    let navigation: NavigationSession
    let traffic: TrafficStore
    let reports: ReportStore
    let premium: PremiumStore
    let cloudSync: CloudSettingsSync
    let haptics = Haptics()

    /// Whether night styling is active right now, from the day/night setting.
    private(set) var nightActive = false
    private(set) var carPlayConnected = false
    var pendingImport: PendingThemeImport?
    var importError: String?

    private var dayNightTimer: Timer?

    private init() {
        configuration = .current
        settings = SettingsStore()
        themes = ThemeStore()
        location = LocationManager()
        reachability = Reachability()
        persistence = PersistenceController()
        routing = MapKitRoutingService()
        search = MapKitSearchService()
        voice = VoiceGuidanceManager()
        premium = PremiumStore(productIDs: configuration.premiumProductIDs)
        cloudSync = CloudSettingsSync()

        let installID = InstallIdentity.current
        let incidentService: IncidentService
        let reportService: CommunityReportService
        if let url = configuration.backendBaseURL {
            let client = OxydeBackendClient(baseURL: url, installID: installID)
            incidentService = client
            reportService = client
        } else {
            incidentService = UnconfiguredIncidentService()
            reportService = UnconfiguredReportService()
        }
        traffic = TrafficStore(service: incidentService)
        reports = ReportStore(service: reportService)
        navigation = NavigationSession(routing: routing, location: location, voice: voice, settings: settings,
                                       persistence: persistence, traffic: traffic)

        cloudSync.attach(to: settings)
        refreshDayNight()
        dayNightTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDayNight() }
        }
        Task { await premium.start() }
    }

    // MARK: Theme resolution

    /// The theme the map should render now: day/night choice, then premium gating.
    var activeTheme: MapTheme {
        let id = settings.value.activeThemeID(nightActive: nightActive)
        let theme = themes.theme(id: id) ?? ThemeRegistry.theme(id: ThemeRegistry.defaultThemeID)!
        if theme.isPremium && !premium.isUnlocked { return ThemeRegistry.theme(id: ThemeRegistry.defaultThemeID)! }
        return theme
    }

    /// CarPlay uses its chosen theme, or the phone's active theme.
    var carPlayTheme: MapTheme {
        if let id = settings.value.carPlayThemeID, let t = themes.theme(id: id), !t.isPremium || premium.isUnlocked { return t }
        return activeTheme
    }

    var accentColor: Color {
        Color(hex: settings.value.accentOverride ?? activeTheme.interface.accent)
    }

    var preferredColorScheme: ColorScheme? {
        activeTheme.isDark(nightActive: nightActive) ? .dark : .light
    }

    var activeEngine: MapEngine {
        settings.value.mapEngine == .vector && configuration.vectorEngineAvailable ? .vector : .appleMaps
    }

    func refreshDayNight() {
        let night: Bool
        switch settings.value.dayNightMode {
        case .off:
            night = false
        case .system:
            night = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        case .sunTimes:
            if let c = location.lastFix?.coordinate {
                night = SolarCalculator.isNight(at: Date(), coordinate: c)
            } else {
                night = UIScreen.main.traitCollection.userInterfaceStyle == .dark
            }
        }
        if night != nightActive { nightActive = night }
    }

    func setCarPlayConnected(_ connected: Bool) { carPlayConnected = connected }

    // MARK: Links

    struct PendingThemeImport: Identifiable {
        let id = UUID()
        let theme: MapTheme
    }

    func handle(url: URL) {
        if url.scheme == ThemeCodec.linkScheme, url.host == "theme" {
            do { pendingImport = PendingThemeImport(theme: try ThemeCodec.theme(fromLink: url)) }
            catch { importError = error.localizedDescription }
            return
        }
        if url.pathExtension == ThemeCodec.fileExtension {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { pendingImport = PendingThemeImport(theme: try ThemeCodec.importData(Data(contentsOf: url))) }
            catch { importError = error.localizedDescription }
            return
        }
        if url.scheme == ThemeCodec.linkScheme, url.host == "place",
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let lat = items.first(where: { $0.name == "lat" })?.value.flatMap(Double.init),
           let lon = items.first(where: { $0.name == "lon" })?.value.flatMap(Double.init) {
            let name = items.first(where: { $0.name == "name" })?.value ?? "Shared place"
            let c = Coordinate(latitude: lat, longitude: lon)
            guard c.isValid else { return }
            navigation.selectedPlace = Place(id: Place.syntheticID(name: name, coordinate: c), name: name,
                                             coordinate: c, provider: "Shared link")
        }
    }
}
