import MapKit
import UIKit
import OxydeCore

/// Route overlays carry their role so the delegate can style them from the theme.
final class RoutePolyline: MKPolyline {
    enum Role { case glow, casing, primary, alternate, traveled }
    var role: Role = .primary
    var routeID: UUID?

    static func make(_ coords: [Coordinate], role: Role, routeID: UUID?) -> RoutePolyline {
        let cl = coords.map(\.cl)
        let p = RoutePolyline(coordinates: cl, count: cl.count)
        p.role = role
        p.routeID = routeID
        return p
    }
}

final class PlaceAnnotation: NSObject, MKAnnotation {
    let place: Place
    var isSelected: Bool
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { place.name }
    var subtitle: String? { place.address }
    init(place: Place, isSelected: Bool) {
        self.place = place
        self.isSelected = isSelected
        coordinate = place.coordinate.cl
    }
}

final class IncidentAnnotation: NSObject, MKAnnotation {
    let incident: Incident
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { incident.title }
    var subtitle: String? { incident.source.attribution }
    init(_ incident: Incident) {
        self.incident = incident
        coordinate = incident.coordinate.cl
    }
}

final class WaypointAnnotation: NSObject, MKAnnotation {
    let waypoint: Waypoint
    let isFinal: Bool
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { waypoint.name }
    init(_ waypoint: Waypoint, isFinal: Bool) {
        self.waypoint = waypoint
        self.isFinal = isFinal
        coordinate = waypoint.coordinate.cl
    }
}

final class VehicleAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var bearing: Double = 0
    init(_ c: CLLocationCoordinate2D) { coordinate = c }
}

/// Draws the navigation puck: an accent arrowhead with a soft glow.
final class VehicleAnnotationView: MKAnnotationView {
    private let arrow = UIImageView()
    var tint: UIColor = .systemBlue { didSet { render() } }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        arrow.frame = bounds
        addSubview(arrow)
        displayPriority = .required
        zPriority = .max
        collisionMode = .none
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setRotation(_ degrees: Double) {
        arrow.transform = CGAffineTransform(rotationAngle: CGFloat(degrees * .pi / 180))
    }

    private func render() {
        let size = CGSize(width: 44, height: 44)
        arrow.image = UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            g.setShadow(offset: .zero, blur: 10, color: tint.withAlphaComponent(0.8).cgColor)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 6, y: 6, width: 32, height: 32)).fill()
            g.setShadow(offset: .zero, blur: 0, color: nil)
            tint.setFill()
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 22, y: 10))
            p.addLine(to: CGPoint(x: 32, y: 33))
            p.addLine(to: CGPoint(x: 22, y: 27))
            p.addLine(to: CGPoint(x: 12, y: 33))
            p.close()
            p.fill()
        }
    }
}

/// Apple MapKit implementation of `MapController`. Themes map onto real MapKit
/// configuration (`MKStandardMapConfiguration`, `MKHybridMapConfiguration`,
/// `MKImageryMapConfiguration`, POI filters, traffic, elevation, emphasis and
/// light/dark), and Oxyde draws the route, markers and camera itself.
@MainActor
final class MapKitMapController: NSObject, MapController {
    let surface: MapSurface
    private let mapView = MKMapView()
    var view: UIView { mapView }

    var onLongPress: ((Coordinate) -> Void)?
    var onSelectPlace: ((Place) -> Void)?
    var onSelectIncident: ((Incident) -> Void)?
    var onUserGesture: (() -> Void)?
    var onCameraHeadingChange: ((Double) -> Void)?

    private var theme: MapTheme = ThemeRegistry.theme(id: ThemeRegistry.defaultThemeID)!
    private var nightActive = false
    private var settings = AppSettings()
    private var appliedConfigKey: String?

    private var routes: [Route] = []
    private var selectedRouteID: UUID?
    private var traveled: Double?
    private var drawnTraveled: Double?
    private var routeOverlays: [MKOverlay] = []

    private var vehicle: VehicleAnnotation?
    private var lastVehicleBearing: Double = 0
    private var isRegionChangeFromUser = false

    init(surface: MapSurface) {
        self.surface = surface
        super.init()
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .includingAll
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = surface != .carPlay
        mapView.register(VehicleAnnotationView.self, forAnnotationViewWithReuseIdentifier: "vehicle")
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "marker")
        if surface == .phone {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            mapView.addGestureRecognizer(press)
        }
        if surface == .preview {
            mapView.isUserInteractionEnabled = false
            mapView.showsUserLocation = false
        }
    }

    // MARK: Theme

    func apply(theme: MapTheme, nightActive: Bool, settings: AppSettings) {
        let previousTheme = self.theme
        self.theme = theme
        self.nightActive = nightActive
        self.settings = settings

        let dark = surface == .carPlay ? (theme.carPlay.alwaysDark || theme.isDark(nightActive: nightActive))
                                       : theme.isDark(nightActive: nightActive)
        let showsTraffic = (surface == .carPlay ? theme.carPlay.showsTraffic : theme.showsTraffic) && settings.showsTraffic
        let poi: POIVisibility = settings.showsPOI ? theme.poiVisibility : .none
        let key = "\(theme.baseMap)-\(theme.elevation)-\(theme.emphasis)-\(poi)-\(showsTraffic)-\(theme.showsBuildings)-\(dark)"

        if key != appliedConfigKey {
            let change = {
                self.mapView.preferredConfiguration = Self.configuration(for: theme, poi: poi, traffic: showsTraffic)
                self.mapView.showsBuildings = theme.showsBuildings
                self.mapView.overrideUserInterfaceStyle = dark ? .dark : .light
            }
            if appliedConfigKey == nil || surface == .carPlay {
                change() // No decorative transitions on the car display.
            } else {
                UIView.transition(with: mapView, duration: 0.35, options: [.transitionCrossDissolve, .allowUserInteraction],
                                  animations: change)
            }
            appliedConfigKey = key
        }
        if previousTheme.resolvedRoute(nightActive: nightActive) != theme.resolvedRoute(nightActive: nightActive) || routeOverlays.isEmpty {
            redrawRoutes()
        }
        if let v = vehicle, let view = mapView.view(for: v) as? VehicleAnnotationView {
            view.tint = UIColor(hex: settings.accentOverride ?? theme.interface.accent)
        }
    }

    static func configuration(for theme: MapTheme, poi: POIVisibility, traffic: Bool) -> MKMapConfiguration {
        let elevation: MKMapConfiguration.ElevationStyle = theme.elevation == .realistic ? .realistic : .flat
        let filter: MKPointOfInterestFilter
        switch poi {
        case .all: filter = .includingAll
        case .none: filter = .excludingAll
        case .driving:
            filter = MKPointOfInterestFilter(including: [.gasStation, .evCharger, .parking, .restaurant, .cafe,
                                                          .restroom, .hospital, .hotel, .foodMarket])
        }
        switch theme.baseMap {
        case .standard:
            let c = MKStandardMapConfiguration(elevationStyle: elevation,
                                               emphasisStyle: theme.emphasis == .muted ? .muted : .default)
            c.pointOfInterestFilter = filter
            c.showsTraffic = traffic
            return c
        case .hybrid:
            let c = MKHybridMapConfiguration(elevationStyle: elevation)
            c.pointOfInterestFilter = filter
            c.showsTraffic = traffic
            return c
        case .satellite:
            return MKImageryMapConfiguration(elevationStyle: elevation)
        }
    }

    // MARK: Routes

    func setRoutes(_ routes: [Route], selectedID: UUID?, traveledDistance: Double?) {
        let routesChanged = routes.map(\.id) != self.routes.map(\.id) || selectedID != selectedRouteID
        self.routes = routes
        self.selectedRouteID = selectedID
        self.traveled = traveledDistance
        // Re-splitting the line every fix is wasteful; 20 m steps look continuous.
        let traveledChanged: Bool = {
            switch (traveledDistance, drawnTraveled) {
            case (nil, nil): return false
            case let (a?, b?): return abs(a - b) >= 20
            default: return true
            }
        }()
        if routesChanged || traveledChanged { redrawRoutes() }
    }

    private func redrawRoutes() {
        mapView.removeOverlays(routeOverlays)
        routeOverlays = []
        drawnTraveled = traveled
        guard !routes.isEmpty else { return }
        let selected = routes.first { $0.id == selectedRouteID } ?? routes[0]
        let style = theme.resolvedRoute(nightActive: nightActive)

        for alt in routes where alt.id != selected.id {
            routeOverlays.append(RoutePolyline.make(alt.coordinates, role: .alternate, routeID: alt.id))
        }
        var remaining = selected.coordinates
        if let traveled, traveled > 0 {
            let split = MeasuredPolyline(selected.coordinates).split(atDistance: traveled)
            remaining = split.remaining
            if split.traveled.count > 1 {
                routeOverlays.append(RoutePolyline.make(split.traveled, role: .traveled, routeID: selected.id))
            }
        }
        let glowEnabled = style.glow > 0.01 && surface != .carPlay
        if glowEnabled { routeOverlays.append(RoutePolyline.make(remaining, role: .glow, routeID: selected.id)) }
        if style.casingWidth > 0 { routeOverlays.append(RoutePolyline.make(remaining, role: .casing, routeID: selected.id)) }
        routeOverlays.append(RoutePolyline.make(remaining, role: .primary, routeID: selected.id))
        mapView.addOverlays(routeOverlays, level: .aboveRoads)
    }

    // MARK: Annotations

    func setIncidents(_ incidents: [Incident]) {
        let existing = mapView.annotations.compactMap { $0 as? IncidentAnnotation }
        let existingIDs = Set(existing.map(\.incident.id))
        let newIDs = Set(incidents.map(\.id))
        mapView.removeAnnotations(existing.filter { !newIDs.contains($0.incident.id) })
        mapView.addAnnotations(incidents.filter { !existingIDs.contains($0.id) }.map(IncidentAnnotation.init))
    }

    func setPlaces(_ places: [Place], selectedID: String?) {
        mapView.removeAnnotations(mapView.annotations.filter { $0 is PlaceAnnotation })
        mapView.addAnnotations(places.map { PlaceAnnotation(place: $0, isSelected: $0.id == selectedID) })
        if let selectedID, let a = mapView.annotations.compactMap({ $0 as? PlaceAnnotation }).first(where: { $0.place.id == selectedID }) {
            mapView.selectAnnotation(a, animated: true)
        }
    }

    func setDestinations(_ waypoints: [Waypoint]) {
        mapView.removeAnnotations(mapView.annotations.filter { $0 is WaypointAnnotation })
        mapView.addAnnotations(waypoints.enumerated().map { WaypointAnnotation($0.element, isFinal: $0.offset == waypoints.count - 1) })
    }

    func setVehicle(_ coordinate: Coordinate?, bearing: Double?) {
        guard let coordinate else {
            if let v = vehicle { mapView.removeAnnotation(v) }
            vehicle = nil
            mapView.showsUserLocation = surface != .preview
            return
        }
        if let b = bearing { lastVehicleBearing = b }
        if let v = vehicle {
            UIView.animate(withDuration: 0.9, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]) {
                v.coordinate = coordinate.cl
            }
            v.bearing = lastVehicleBearing
            updateVehicleRotation()
        } else {
            let v = VehicleAnnotation(coordinate.cl)
            v.bearing = lastVehicleBearing
            vehicle = v
            mapView.showsUserLocation = false
            mapView.addAnnotation(v)
        }
    }

    private func updateVehicleRotation() {
        guard let v = vehicle, let view = mapView.view(for: v) as? VehicleAnnotationView else { return }
        view.setRotation(v.bearing - mapView.camera.heading)
    }

    // MARK: Camera

    func follow(_ coordinate: Coordinate, bearing: Double, speed: Double, animated: Bool) {
        let heading = settings.cameraMode == .northUp ? 0 : bearing
        let camera = MKMapCamera(lookingAtCenter: coordinate.cl,
                                 fromDistance: followDistance(theme: theme, settings: settings, speed: speed),
                                 pitch: CGFloat(followPitch(theme: theme, settings: settings)),
                                 heading: heading)
        isRegionChangeFromUser = false
        if animated {
            UIView.animate(withDuration: 0.9, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]) {
                self.mapView.camera = camera
            }
        } else {
            mapView.setCamera(camera, animated: false)
        }
    }

    func showOverview(of coordinates: [Coordinate], edgePadding: UIEdgeInsets, animated: Bool) {
        guard !coordinates.isEmpty else { return }
        let cl = coordinates.map(\.cl)
        let poly = MKPolyline(coordinates: cl, count: cl.count)
        mapView.setVisibleMapRect(poly.boundingMapRect, edgePadding: edgePadding, animated: animated)
    }

    func center(on coordinate: Coordinate, distance: Double?, animated: Bool) {
        let camera = MKMapCamera(lookingAtCenter: coordinate.cl, fromDistance: distance ?? mapView.camera.centerCoordinateDistance,
                                 pitch: mapView.camera.pitch, heading: mapView.camera.heading)
        mapView.setCamera(camera, animated: animated)
    }

    func zoom(by factor: Double) {
        let camera = mapView.camera.copy() as! MKMapCamera
        camera.centerCoordinateDistance = max(150, min(5_000_000, camera.centerCoordinateDistance * factor))
        mapView.setCamera(camera, animated: true)
    }

    func resetNorth() {
        let camera = mapView.camera.copy() as! MKMapCamera
        camera.heading = 0
        mapView.setCamera(camera, animated: true)
    }

    func pan(by offset: CGPoint) {
        let center = CGPoint(x: mapView.bounds.midX + offset.x, y: mapView.bounds.midY + offset.y)
        let c = mapView.convert(center, toCoordinateFrom: mapView)
        mapView.setCenter(c, animated: true)
        onUserGesture?()
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let c = mapView.convert(g.location(in: mapView), toCoordinateFrom: mapView)
        onLongPress?(Coordinate(c))
    }
}

extension MapKitMapController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let line = overlay as? RoutePolyline else { return MKOverlayRenderer(overlay: overlay) }
        let style = theme.resolvedRoute(nightActive: nightActive)
        let r = MKPolylineRenderer(polyline: line)
        r.lineCap = .round
        r.lineJoin = .round
        let carScale = surface == .carPlay ? theme.carPlay.routeWidth / max(style.width, 1) : 1
        let width = CGFloat(style.width * carScale)
        let primary = surface == .carPlay ? theme.carPlay.routeColor : style.color
        switch line.role {
        case .primary:
            r.strokeColor = UIColor(hex: primary)
            r.lineWidth = width
        case .casing:
            r.strokeColor = UIColor(hex: style.casingColor)
            r.lineWidth = width + CGFloat(style.casingWidth * 2)
        case .glow:
            r.strokeColor = UIColor(hex: style.glowColor).withAlphaComponent(CGFloat(0.12 + 0.28 * style.glow))
            r.lineWidth = width * CGFloat(2.2 + 1.6 * style.glow)
        case .alternate:
            r.strokeColor = UIColor(hex: style.alternateColor).withAlphaComponent(0.85)
            r.lineWidth = width * 0.75
        case .traveled:
            r.strokeColor = UIColor(hex: style.traveledColor).withAlphaComponent(0.8)
            r.lineWidth = width * 0.8
        }
        return r
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let accent = UIColor(hex: settings.accentOverride ?? theme.interface.accent)
        switch annotation {
        case is VehicleAnnotation:
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "vehicle", for: annotation) as! VehicleAnnotationView
            v.tint = accent
            v.setRotation((annotation as! VehicleAnnotation).bearing - mapView.camera.heading)
            return v
        case let a as PlaceAnnotation:
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "marker", for: annotation) as! MKMarkerAnnotationView
            v.markerTintColor = accent
            v.glyphImage = UIImage(systemName: a.place.category?.symbol ?? "mappin")
            v.titleVisibility = .adaptive
            v.displayPriority = .required
            v.canShowCallout = false
            return v
        case let a as IncidentAnnotation:
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "marker", for: annotation) as! MKMarkerAnnotationView
            v.markerTintColor = a.incident.source.isVerifiedProvider ? .systemRed : .systemOrange
            v.glyphImage = UIImage(systemName: Self.symbol(for: a.incident.kind))
            v.titleVisibility = .hidden
            v.displayPriority = .defaultHigh
            v.canShowCallout = false
            return v
        case let a as WaypointAnnotation:
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "marker", for: annotation) as! MKMarkerAnnotationView
            v.markerTintColor = a.isFinal ? accent : .systemGray
            v.glyphImage = UIImage(systemName: a.isFinal ? "flag.checkered" : "smallcircle.filled.circle")
            v.displayPriority = .required
            return v
        default:
            return nil
        }
    }

    static func symbol(for kind: IncidentKind) -> String {
        switch kind {
        case .accident: return "car.side.rear.and.collision.and.car.side.front"
        case .congestion: return "car.2.fill"
        case .roadworks: return "cone.fill"
        case .closure, .laneClosure: return "xmark.octagon.fill"
        case .hazard: return "exclamationmark.triangle.fill"
        case .weather: return "cloud.rain.fill"
        case .event: return "calendar"
        case .police: return "shield.lefthalf.filled"
        case .speedCamera: return "camera.fill"
        case .other: return "exclamationmark.circle.fill"
        }
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
        switch annotation {
        case let a as PlaceAnnotation: onSelectPlace?(a.place)
        case let a as IncidentAnnotation: onSelectIncident?(a.incident)
        default: break
        }
        if !(annotation is PlaceAnnotation) { mapView.deselectAnnotation(annotation, animated: false) }
    }

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        // A region change driven by a gesture recognizer means the user moved the map.
        let gestures = mapView.subviews.first?.gestureRecognizers ?? []
        if gestures.contains(where: { $0.state == .began || $0.state == .changed }) {
            isRegionChangeFromUser = true
            onUserGesture?()
        }
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        updateVehicleRotation()
        onCameraHeadingChange?(mapView.camera.heading)
    }
}
