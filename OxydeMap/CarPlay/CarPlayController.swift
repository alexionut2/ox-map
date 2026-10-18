import CarPlay
import MapKit
import Observation
import UIKit
import OxydeCore

/// Hosts the map in the CarPlay window. CarPlay navigation apps draw their own map in
/// this base view; everything else on the car screen is an Apple template.
@MainActor
final class CarPlayMapViewController: UIViewController {
    let map: MapController
    /// Called when the car switches between light and dark (headlights, time of day).
    var onAppearanceChange: (() -> Void)?
    private var observingTraits = false

    init(map: MapController) {
        self.map = map
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let v = map.view
        v.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: view.leadingAnchor), v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            v.topAnchor.constraint(equalTo: view.topAnchor), v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !observingTraits else { return }
        observingTraits = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: CarPlayMapViewController, _: UITraitCollection) in
            vc.onAppearanceChange?()
        }
    }
}

/// Drives the CarPlay templates from the shared `NavigationSession`, so a trip started on
/// either screen shows the same route, maneuvers and estimates on both.
@MainActor
final class CarPlayController: NSObject {
    private let interfaceController: CPInterfaceController
    private let window: CPWindow
    private let model: AppModel
    private let mapVC: CarPlayMapViewController
    private let mapTemplate = CPMapTemplate()

    private var listenerID: UUID?
    private var navSession: CPNavigationSession?
    private var activeTrip: CPTrip?
    private var previewTrip: CPTrip?
    private var shownManeuverStep: Int?
    private var isFollowing = true
    private var searchTask: Task<Void, Never>?
    private var lastSearchResults: [Place] = []
    private var connected = false

    init(interfaceController: CPInterfaceController, window: CPWindow, model: AppModel) {
        self.interfaceController = interfaceController
        self.window = window
        self.model = model
        // CarPlay always uses MapKit: it is the engine certified for the car display path.
        mapVC = CarPlayMapViewController(map: MapKitMapController(surface: .carPlay))
        super.init()
    }

    private var nav: NavigationSession { model.navigation }
    private var carIsDark: Bool { interfaceController.carTraitCollection.userInterfaceStyle == .dark }

    // MARK: Lifecycle

    func connect() {
        connected = true
        window.rootViewController = mapVC
        mapVC.onAppearanceChange = { [weak self] in
            self?.applyTheme()
            self?.shownManeuverStep = nil
        }
        mapTemplate.mapDelegate = self
        mapTemplate.automaticallyHidesNavigationBar = true
        configureButtons()
        interfaceController.setRootTemplate(mapTemplate, animated: false, completion: nil)
        applyTheme()
        observeAppearance()
        listenerID = nav.addListener { [weak self] e in self?.handle(e) }
        syncWithPhone()
        if let c = model.location.lastFix?.coordinate { mapVC.map.center(on: c, distance: 1200, animated: false) }
        if model.location.permission.isAuthorized, model.location.mode == .off { model.location.setMode(.browsing) }
    }

    func disconnect() {
        connected = false
        if let id = listenerID { nav.removeListener(id) }
        searchTask?.cancel()
    }

    /// Re-applies the theme whenever the CarPlay theme, settings or day/night state change.
    private func observeAppearance() {
        guard connected else { return }
        withObservationTracking {
            _ = model.carPlayTheme
            _ = model.settings.value
            _ = model.nightActive
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTheme()
                self?.observeAppearance()
            }
        }
    }

    private func applyTheme() {
        let theme = model.carPlayTheme
        mapVC.map.apply(theme: theme, nightActive: carIsDark || model.nightActive, settings: model.settings.value)
        mapTemplate.guidanceBackgroundColor = theme.isDark(nightActive: carIsDark) || theme.carPlay.alwaysDark
            ? UIColor(hex: "#111317") : .systemBackground
        mapTemplate.tripEstimateStyle = carIsDark || theme.carPlay.alwaysDark ? .dark : .light
    }

    // MARK: Buttons

    private func configureButtons() {
        let search = CPBarButton(image: UIImage(systemName: "magnifyingglass")!) { [weak self] _ in self?.showSearch() }
        let places = CPBarButton(image: UIImage(systemName: "star.fill")!) { [weak self] _ in self?.showPlaces() }
        let report = CPBarButton(image: UIImage(systemName: "exclamationmark.bubble.fill")!) { [weak self] _ in self?.showReports() }
        mapTemplate.leadingNavigationBarButtons = [search, places]
        mapTemplate.trailingNavigationBarButtons = model.reports.isConfigured ? [report] : []

        let zoomIn = CPMapButton { [weak self] _ in self?.mapVC.map.zoom(by: 0.6) }
        zoomIn.image = UIImage(systemName: "plus.magnifyingglass")
        let zoomOut = CPMapButton { [weak self] _ in self?.mapVC.map.zoom(by: 1.6) }
        zoomOut.image = UIImage(systemName: "minus.magnifyingglass")
        let recenter = CPMapButton { [weak self] _ in self?.recenter() }
        recenter.image = UIImage(systemName: "location.fill")
        let pan = CPMapButton { [weak self] _ in self?.mapTemplate.showPanningInterface(animated: true) }
        pan.image = UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")
        mapTemplate.mapButtons = [recenter, zoomIn, zoomOut, pan]
    }

    private func recenter() {
        isFollowing = true
        if nav.phase == .navigating, let p = nav.progress {
            mapVC.map.follow(p.snappedCoordinate, bearing: p.routeBearing, speed: max(0, nav.lastFix?.speed ?? 0), animated: true)
        } else if let c = model.location.lastFix?.coordinate {
            mapVC.map.center(on: c, distance: 1200, animated: true)
        }
    }

    // MARK: Session events

    private func syncWithPhone() {
        switch nav.phase {
        case .previewing: showPreviews()
        case .navigating: startCarSession()
        default: break
        }
        updateMap()
    }

    private func handle(_ e: SessionEvent) {
        switch e {
        case .routesChanged:
            updateMap()
            if nav.phase == .previewing { showPreviews() }
            if nav.phase == .idle { mapTemplate.hideTripPreviews(); previewTrip = nil }
        case .started:
            mapTemplate.hideTripPreviews()
            startCarSession()
            updateMap()
        case .progress(let p):
            updateProgress(p)
        case .maneuverChanged:
            shownManeuverStep = nil
            if let p = nav.progress { updateProgress(p) }
        case .rerouting:
            navSession?.pauseTrip(for: .rerouting, description: "Finding a new route")
        case .rerouted:
            shownManeuverStep = nil
            updateMap()
            if let p = nav.progress { updateProgress(p) }
        case .arrived:
            navSession?.finishTrip()
            navSession = nil
            activeTrip = nil
            updateMap()
        case .ended:
            navSession?.cancelTrip()
            navSession = nil
            activeTrip = nil
            mapTemplate.hideTripPreviews()
            updateMap()
        case .alert(let title, let subtitle):
            presentAlert(title: title, subtitle: subtitle)
        }
    }

    private func updateMap() {
        mapVC.map.setRoutes(nav.routes, selectedID: nav.selectedRouteID,
                            traveledDistance: nav.phase == .navigating ? nav.progress?.distanceTraveled : nil)
        mapVC.map.setDestinations(nav.stops)
        mapVC.map.setIncidents(model.traffic.visibleIncidents(settings: model.settings.value))
        if nav.phase == .previewing {
            mapVC.map.showOverview(of: nav.routes.flatMap(\.coordinates),
                                   edgePadding: UIEdgeInsets(top: 60, left: 280, bottom: 40, right: 40), animated: true)
        }
        if nav.phase != .navigating { mapVC.map.setVehicle(nil, bearing: nil) }
    }

    // MARK: Previews

    private func trip(for routes: [Route]) -> CPTrip? {
        guard let dest = routes.first?.destination ?? nav.stops.last else { return nil }
        let units = model.settings.value.resolvedUnits
        let comps = Dictionary(uniqueKeysWithValues: RouteComparison.compare(routes).map { ($0.routeID, $0) })
        let choices = routes.map { r -> CPRouteChoice in
            let time = DurationFormatter.short(r.expectedTravelTime)
            let dist = DistanceFormatter.guidance(meters: r.distance, system: units).display
            let label = comps[r.id]?.isFastest == true ? "Fastest" : DurationFormatter.delta(comps[r.id]?.timeDelta ?? 0)
            let name = r.name.isEmpty ? label : r.name
            let choice = CPRouteChoice(summaryVariants: [name, label],
                                       additionalInformationVariants: ["\(time) · \(dist)\(r.hasTolls ? " · Tolls" : "")", "\(time) · \(dist)"],
                                       selectionSummaryVariants: [time])
            choice.userInfo = r.id
            return choice
        }
        let t = CPTrip(origin: MKMapItem.forCurrentLocation(), destination: dest.mapItem, routeChoices: choices)
        t.userInfo = dest.id
        return t
    }

    private func showPreviews() {
        if let error = nav.planningError {
            presentAlert(title: "No route", subtitle: error)
            return
        }
        guard !nav.routes.isEmpty, let t = trip(for: nav.routes) else { return }
        previewTrip = t
        let text = CPTripPreviewTextConfiguration(startButtonTitle: "Go", additionalRoutesButtonTitle: "Routes", overviewButtonTitle: "Overview")
        mapTemplate.showTripPreviews([t], textConfiguration: text)
    }

    // MARK: Guidance

    private func startCarSession() {
        guard navSession == nil, let route = nav.activeRoute, let t = trip(for: [route]) else { return }
        activeTrip = t
        navSession = mapTemplate.startNavigationSession(for: t)
        shownManeuverStep = nil
        isFollowing = true
        if let p = nav.progress { updateProgress(p) }
    }

    private func updateProgress(_ p: RouteProgress) {
        mapVC.map.setRoutes(nav.routes, selectedID: nav.selectedRouteID, traveledDistance: p.distanceTraveled)
        mapVC.map.setVehicle(p.snappedCoordinate, bearing: p.routeBearing)
        if isFollowing {
            mapVC.map.follow(p.snappedCoordinate, bearing: p.routeBearing, speed: max(0, nav.lastFix?.speed ?? 0), animated: true)
        }
        guard let session = navSession, let route = nav.activeRoute else { return }

        if shownManeuverStep != p.upcomingStepIndex {
            shownManeuverStep = p.upcomingStepIndex
            var maneuvers: [CPManeuver] = []
            if let i = p.upcomingStepIndex, route.steps.indices.contains(i) {
                maneuvers.append(maneuver(route.steps[i], distance: p.distanceToUpcomingManeuver ?? 0, progress: p))
            }
            if let f = p.followingStepIndex, route.steps.indices.contains(f), let gap = p.distanceFromUpcomingToFollowing {
                maneuvers.append(maneuver(route.steps[f], distance: gap, progress: p))
            }
            session.upcomingManeuvers = maneuvers
        }
        if let current = session.upcomingManeuvers.first, let d = p.distanceToUpcomingManeuver {
            session.updateEstimates(estimates(distance: d, progress: p), for: current)
        }
        if let t = activeTrip {
            mapTemplate.update(CPTravelEstimates(distanceRemaining: Measurement(value: p.distanceRemaining, unit: UnitLength.meters),
                                                 timeRemaining: p.timeRemaining),
                               for: t, with: .default)
        }
    }

    /// Time to a maneuver, as the provider's remaining time scaled by distance.
    private func estimates(distance: Double, progress p: RouteProgress) -> CPTravelEstimates {
        let time = p.distanceRemaining > 0 ? p.timeRemaining * distance / p.distanceRemaining : 0
        return CPTravelEstimates(distanceRemaining: Measurement(value: distance, unit: UnitLength.meters), timeRemaining: time)
    }

    private func maneuver(_ step: RouteStep, distance: Double, progress: RouteProgress) -> CPManeuver {
        let m = CPManeuver()
        m.instructionVariants = step.instruction.isEmpty ? [] : [step.instruction]
        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .bold)
        m.symbolImage = UIImage(systemName: step.maneuver.symbolName, withConfiguration: config)?
            .withTintColor(carIsDark ? .white : .black, renderingMode: .alwaysOriginal)
        m.initialTravelEstimates = estimates(distance: distance, progress: progress)
        m.userInfo = step.id
        return m
    }

    // MARK: Alerts

    private func presentAlert(title: String, subtitle: String?) {
        let ok = CPAlertAction(title: "OK", style: .default) { [weak self] _ in self?.mapTemplate.dismissNavigationAlert(animated: true, completion: { _ in }) }
        let alert = CPNavigationAlert(titleVariants: [title], subtitleVariants: subtitle.map { [$0] } ?? [], image: nil,
                                      primaryAction: ok, secondaryAction: nil, duration: 8)
        mapTemplate.present(navigationAlert: alert, animated: true)
    }

    // MARK: Search

    private func showSearch() {
        let search = CPSearchTemplate()
        search.delegate = self
        interfaceController.pushTemplate(search, animated: true, completion: nil)
    }

    fileprivate func listItem(for place: Place) -> CPListItem {
        let units = model.settings.value.resolvedUnits
        var detail = place.address ?? ""
        if let here = model.location.lastFix?.coordinate {
            let d = DistanceFormatter.guidance(meters: GeoMath.distance(here, place.coordinate), system: units).display
            detail = detail.isEmpty ? d : "\(d) · \(detail)"
        }
        let item = CPListItem(text: place.name, detailText: detail,
                              image: UIImage(systemName: place.category?.symbol ?? "mappin.circle.fill"))
        item.userInfo = place
        item.handler = { [weak self] _, completion in
            self?.navigate(to: place)
            completion()
        }
        return item
    }

    private func navigate(to place: Place) {
        interfaceController.popToRootTemplate(animated: true, completion: nil)
        nav.preview(to: place)
    }

    // MARK: Places

    private func showPlaces() {
        let saved = model.persistence.savedPlaces()
        var sections: [CPListSection] = []
        let shortcuts = [SavedPlaceKind.home, .work].compactMap { k in saved.first { $0.kind == k } }
        if !shortcuts.isEmpty {
            sections.append(CPListSection(items: shortcuts.map { s in
                let item = listItem(for: s.place)
                item.setImage(UIImage(systemName: s.kind == .home ? "house.fill" : "briefcase.fill"))
                return item
            }, header: "Shortcuts", sectionIndexTitle: nil))
        }
        let favorites = saved.filter { $0.kind == .favorite }
        if !favorites.isEmpty {
            sections.append(CPListSection(items: favorites.prefix(12).map { listItem(for: $0.place) }, header: "Favorites", sectionIndexTitle: nil))
        }
        let recents = model.persistence.recents(limit: 12)
        if !recents.isEmpty {
            sections.append(CPListSection(items: recents.map { listItem(for: $0.place) }, header: "Recent", sectionIndexTitle: nil))
        }
        if sections.isEmpty {
            sections = [CPListSection(items: [CPListItem(text: "No saved places yet", detailText: "Save places on your iPhone")])]
        }
        let list = CPListTemplate(title: "Places", sections: sections)
        interfaceController.pushTemplate(list, animated: true, completion: nil)
    }

    // MARK: Reports

    private func showReports() {
        let buttons = model.reports.allowedCategories.prefix(8).map { cat in
            CPGridButton(titleVariants: [cat.title], image: UIImage(systemName: cat.symbol)!) { [weak self] _ in
                guard let self else { return }
                self.model.reports.submit(cat, at: self.model.location.lastFix, traffic: self.model.traffic)
                self.interfaceController.popToRootTemplate(animated: true, completion: nil)
                let undo = CPAlertAction(title: "Undo", style: .cancel) { [weak self] _ in
                    self?.model.reports.undo()
                    self?.mapTemplate.dismissNavigationAlert(animated: true, completion: { _ in })
                }
                let alert = CPNavigationAlert(titleVariants: ["Reporting \(cat.title.lowercased())"],
                                              subtitleVariants: ["Shared with other drivers in a few seconds"], image: nil,
                                              primaryAction: undo, secondaryAction: nil, duration: 4)
                self.mapTemplate.present(navigationAlert: alert, animated: true)
            }
        }
        interfaceController.pushTemplate(CPGridTemplate(title: "Report", gridButtons: Array(buttons)), animated: true, completion: nil)
    }
}

// MARK: - CPMapTemplateDelegate

extension CarPlayController: CPMapTemplateDelegate {
    func mapTemplate(_ mapTemplate: CPMapTemplate, selectedPreviewFor trip: CPTrip, using routeChoice: CPRouteChoice) {
        if let id = routeChoice.userInfo as? UUID { nav.selectRoute(id) }
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
        if let id = routeChoice.userInfo as? UUID { nav.selectRoute(id) }
        mapTemplate.hideTripPreviews()
        nav.start()
    }

    func mapTemplateDidCancelNavigation(_ mapTemplate: CPMapTemplate) {
        navSession = nil
        nav.stop()
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, panWith direction: CPMapTemplate.PanDirection) {
        isFollowing = false
        let step: CGFloat = 120
        var offset = CGPoint.zero
        if direction.contains(.left) { offset.x -= step }
        if direction.contains(.right) { offset.x += step }
        if direction.contains(.up) { offset.y -= step }
        if direction.contains(.down) { offset.y += step }
        mapVC.map.pan(by: offset)
    }

    func mapTemplateDidDismissPanningInterface(_ mapTemplate: CPMapTemplate) {}

    func mapTemplate(_ mapTemplate: CPMapTemplate, displayStyleFor maneuver: CPManeuver) -> CPManeuverDisplayStyle {
        .leadingSymbol
    }
}

// MARK: - CPSearchTemplateDelegate

extension CarPlayController: CPSearchTemplateDelegate {
    func searchTemplate(_ searchTemplate: CPSearchTemplate, updatedSearchText searchText: String,
                        completionHandler: @escaping ([CPListItem]) -> Void) {
        searchTask?.cancel()
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { completionHandler([]); return }
        let region = model.location.lastFix.map { SearchRegion(center: $0.coordinate, radius: 30_000) }
        searchTask = Task { [weak self] in
            // Short debounce so each keystroke on the car keyboard doesn't hit the service.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { completionHandler([]); return }
            let results = (try? await self.model.search.search(text: text, near: region)) ?? []
            self.lastSearchResults = results
            completionHandler(Array(results.prefix(CPListTemplate.maximumItemCount)).map { self.listItem(for: $0) })
        }
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate, selectedResult item: CPListItem, completionHandler: @escaping () -> Void) {
        if let place = item.userInfo as? Place { navigate(to: place) }
        completionHandler()
    }

    func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {
        guard !lastSearchResults.isEmpty else { return }
        let list = CPListTemplate(title: "Results", sections: [CPListSection(items: lastSearchResults.prefix(12).map { listItem(for: $0) })])
        interfaceController.pushTemplate(list, animated: true, completion: nil)
    }
}
