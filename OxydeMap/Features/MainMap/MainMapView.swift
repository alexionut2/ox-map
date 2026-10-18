import SwiftUI
import SwiftData
import OxydeCore

enum MainSheet: String, Identifiable {
    case search, studio, settings, reports, saved, trips, layers, diagnostics, premium
    var id: String { rawValue }
}

/// The primary screen: a full-bleed map with only the controls that matter for the
/// current phase (exploring, previewing a route, or driving).
struct MainMapView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(LocationManager.self) private var location
    @Environment(NavigationSession.self) private var nav
    @Environment(\.scenePhase) private var scenePhase

    @State private var handle = MapHandle()
    @State private var isFollowing = true
    @State private var sheet: MainSheet?
    @State private var searchResults: [Place] = []
    @State private var selectedIncident: Incident?
    @State private var mapHeading: Double = 0
    @State private var focusMode = false

    private var hidden: Set<HUDElement> { settings.value.hiddenElements }
    private var theme: MapTheme { model.activeTheme }

    var body: some View {
        ZStack {
            map.ignoresSafeArea()

            VStack(spacing: 10) {
                topArea
                Spacer(minLength: 0)
                bottomArea
            }
            .padding(.horizontal, OX.gutter)
            .padding(.bottom, 8)

            if !focusMode { controlsColumn }
        }
        .sheet(item: $sheet) { s in sheetContent(s) }
        .sheet(item: $selectedIncident) { inc in
            IncidentDetailView(incident: inc).presentationDetents([.medium])
        }
        .onAppear {
            if location.permission.isAuthorized { location.setMode(nav.phase == .navigating ? .navigating : .browsing) }
        }
        .onChange(of: location.permission) { _, p in if p.isAuthorized, location.mode == .off { location.setMode(.browsing) } }
        .onChange(of: location.lastFix) { _, fix in
            guard let fix, nav.phase != .navigating, isFollowing else { return }
            handle.controller?.center(on: fix.coordinate, distance: nil, animated: true)
            Task { await model.traffic.refreshIfNeeded(around: fix.coordinate) }
        }
        .onChange(of: nav.phase) { _, phase in
            switch phase {
            case .previewing: showOverview()
            case .navigating: isFollowing = true
            default: break
            }
        }
        .onChange(of: nav.selectedRouteID) { _, _ in if nav.phase == .previewing { showOverview() } }
        .onChange(of: scenePhase) { _, p in if p == .active { model.refreshDayNight() } }
    }

    // MARK: Map

    private var mapState: MapSceneState {
        let navigating = nav.phase == .navigating
        var places = searchResults
        if let p = nav.selectedPlace, !places.contains(where: { $0.id == p.id }) { places.append(p) }
        return MapSceneState(
            theme: theme, nightActive: model.nightActive, settings: settings.value,
            routes: nav.routes, selectedRouteID: nav.selectedRouteID,
            traveledDistance: navigating ? nav.progress?.distanceTraveled : nil,
            incidents: model.traffic.visibleIncidents(settings: settings.value),
            places: navigating ? [] : places, selectedPlaceID: nav.selectedPlace?.id,
            waypoints: nav.stops,
            vehicle: navigating ? (nav.progress?.snappedCoordinate ?? nav.lastFix?.coordinate) : nil,
            vehicleBearing: navigating ? (nav.progress?.routeBearing ?? nav.lastFix?.course) : nil,
            vehicleSpeed: max(0, nav.lastFix?.speed ?? 0),
            isFollowing: navigating && isFollowing)
    }

    private var map: some View {
        OxydeMapView(engine: model.activeEngine, state: mapState, handle: handle,
                     onLongPress: { c in Task { await dropPin(at: c) } },
                     onSelectPlace: { nav.selectedPlace = $0 },
                     onSelectIncident: { selectedIncident = $0 },
                     onUserGesture: { isFollowing = false },
                     onHeadingChange: { mapHeading = $0 })
            .id(model.activeEngine)
    }

    private func showOverview() {
        let coords = nav.routes.flatMap(\.coordinates)
        handle.controller?.showOverview(of: coords, edgePadding: UIEdgeInsets(top: 140, left: 40, bottom: 360, right: 40), animated: true)
        isFollowing = false
    }

    private func dropPin(at c: Coordinate) async {
        model.haptics.tap(enabled: settings.value.hapticsEnabled)
        isFollowing = false
        if let p = try? await model.search.reverseGeocode(c) {
            nav.selectedPlace = p
        } else {
            nav.selectedPlace = Place(id: Place.syntheticID(name: "Dropped pin", coordinate: c), name: "Dropped pin",
                                      coordinate: c, address: String(format: "%.5f, %.5f", c.latitude, c.longitude),
                                      provider: "Map")
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var topArea: some View {
        if nav.phase == .navigating {
            ManeuverPanel()
            NavigationBanners()
        } else {
            HStack(spacing: 10) {
                Button { sheet = .search } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                        Text("Where to?").foregroundStyle(.secondary)
                        Spacer()
                    }
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .oxPanel(theme.interface.panel, cornerRadius: 25)
                .accessibilityIdentifier("main.search")

                Button { sheet = .settings } label: {
                    Image(systemName: "person.crop.circle").font(.title2).frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .oxPanel(theme.interface.panel, cornerRadius: 25)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("main.settings")
            }
            StatusBanners()
        }
    }

    @ViewBuilder
    private var bottomArea: some View {
        HStack(alignment: .bottom) {
            if !hidden.contains(.speedometer), settings.value.speedometer != .hidden, !focusMode {
                SpeedometerView(fix: location.lastFix, style: settings.value.speedometer, units: settings.value.resolvedUnits,
                                typography: theme.interface.typography)
            }
            Spacer()
        }
        switch nav.phase {
        case .navigating:
            ActiveNavigationBar(onOverview: { showOverview() }, onRecenter: { isFollowing = true })
        case .planning, .previewing:
            RoutePreviewPanel(onAddStop: { sheet = .search })
        case .arrived:
            ArrivalCard()
        case .idle:
            if let place = nav.selectedPlace {
                PlaceCard(place: place)
            } else if let recovery = nav.recovery {
                RecoveryCard(recovery: recovery)
            } else if !hidden.contains(.quickAccess) && !focusMode {
                QuickAccessBar(onSaved: { sheet = .saved }, onTrips: { sheet = .trips })
            }
        }
    }

    private var controlsColumn: some View {
        VStack(spacing: 10) {
            if !hidden.contains(.compass), abs(mapHeading) > 1 {
                FloatingButton(symbol: "location.north.line.fill", label: "Reset to north") { handle.controller?.resetNorth() }
                    .rotationEffect(.degrees(-mapHeading))
            }
            FloatingButton(symbol: isFollowing ? "location.fill" : "location", label: "Current location", isActive: isFollowing) {
                if !location.permission.isAuthorized {
                    if location.permission == .notDetermined { location.requestWhenInUse() } else { sheet = .diagnostics }
                    return
                }
                isFollowing = true
                if nav.phase != .navigating, let c = location.lastFix?.coordinate {
                    handle.controller?.center(on: c, distance: 1500, animated: true)
                }
            }
            .accessibilityIdentifier("main.locate")
            if !hidden.contains(.layersButton) {
                FloatingButton(symbol: "square.3.layers.3d", label: "Map layers") { sheet = .layers }
                    .accessibilityIdentifier("main.layers")
            }
            if !hidden.contains(.studioButton) {
                FloatingButton(symbol: "paintpalette.fill", label: "Map Studio") { sheet = .studio }
                    .accessibilityIdentifier("main.studio")
            }
            if !hidden.contains(.soundButton) {
                FloatingButton(symbol: soundSymbol, label: "Voice guidance") { cycleGuidance() }
            }
            if !hidden.contains(.reportButton) {
                FloatingButton(symbol: "exclamationmark.bubble.fill", label: "Report") { sheet = .reports }
                    .accessibilityIdentifier("main.report")
            }
            FloatingButton(symbol: focusMode ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward",
                           label: focusMode ? "Show controls" : "Clean view", size: 40) { focusMode.toggle() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, OX.gutter)
        .padding(.top, nav.phase == .navigating ? 190 : 90)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            if focusMode {
                FloatingButton(symbol: "rectangle.arrowtriangle.2.inward", label: "Show controls", size: 40) { focusMode = false }
                    .padding(.trailing, OX.gutter).padding(.top, 90)
            }
        }
    }

    private var soundSymbol: String {
        switch settings.value.voice.guidanceLevel {
        case .full: return "speaker.wave.3.fill"
        case .alertsOnly: return "speaker.wave.1.fill"
        case .muted: return "speaker.slash.fill"
        }
    }

    private func cycleGuidance() {
        let all = GuidanceLevel.allCases
        let i = all.firstIndex(of: settings.value.voice.guidanceLevel) ?? 0
        settings.value.voice.guidanceLevel = all[(i + 1) % all.count]
    }

    @ViewBuilder
    private func sheetContent(_ s: MainSheet) -> some View {
        switch s {
        case .search:
            SearchView(results: $searchResults, onPick: { place in
                sheet = nil
                isFollowing = false
                if nav.phase == .previewing || nav.phase == .planning || nav.phase == .navigating {
                    nav.addStop(place)
                } else {
                    nav.selectedPlace = place
                    handle.controller?.center(on: place.coordinate, distance: 1500, animated: true)
                }
            })
            .presentationDetents([.large])
        case .studio: MapStudioView()
        case .settings: SettingsView()
        case .reports: ReportSheet().presentationDetents([.medium, .large])
        case .saved: SavedPlacesView(onPick: { place in sheet = nil; nav.selectedPlace = place })
        case .trips: TripDashboardView()
        case .layers: LayersSheet().presentationDetents([.medium])
        case .diagnostics: NavigationStack { DiagnosticsView() }
        case .premium: PremiumView()
        }
    }
}

