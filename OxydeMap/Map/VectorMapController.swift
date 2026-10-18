#if canImport(MapLibre)
import MapLibre
import UIKit
import OxydeCore

/// Vector engine built on MapLibre Native. It renders the theme's full palette (roads,
/// land, water, buildings, labels) from the style document compiled by
/// `VectorStyleBuilder`. Compiled only when the MapLibre package is added to the
/// project (see docs/PROVIDERS.md); otherwise the app uses MapKit everywhere.
@MainActor
final class VectorMapController: NSObject, MapController, MLNMapViewDelegate {
    let surface: MapSurface
    private let tiles: VectorTileConfiguration
    private let mapView: MLNMapView
    var view: UIView { mapView }

    var onLongPress: ((Coordinate) -> Void)?
    var onSelectPlace: ((Place) -> Void)?
    var onSelectIncident: ((Incident) -> Void)?
    var onUserGesture: (() -> Void)?
    var onCameraHeadingChange: ((Double) -> Void)?

    private var theme = ThemeRegistry.theme(id: ThemeRegistry.defaultThemeID)!
    private var nightActive = false
    private var settings = AppSettings()
    private var styleKey: String?
    private var styleLoaded = false

    private var routes: [Route] = []
    private var selectedRouteID: UUID?
    private var traveled: Double?
    private var incidents: [Incident] = []
    private var placeAnnotations: [MLNPointAnnotation: Place] = [:]
    private var waypointAnnotations: [MLNPointAnnotation] = []

    init(surface: MapSurface, tiles: VectorTileConfiguration) {
        self.surface = surface
        self.tiles = tiles
        mapView = MLNMapView(frame: .zero)
        super.init()
        mapView.delegate = self
        mapView.showsUserLocation = surface != .preview
        mapView.compassView.isHidden = true
        mapView.logoView.isHidden = false
        mapView.attributionButton.isHidden = false
        mapView.isUserInteractionEnabled = surface != .preview
        if surface == .phone {
            mapView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:))))
        }
    }

    func apply(theme: MapTheme, nightActive: Bool, settings: AppSettings) {
        self.theme = theme
        self.nightActive = nightActive
        self.settings = settings
        var effective = theme
        effective.palette.labelDensity = settings.labelDensity
        if !settings.showsPOI { effective.poiVisibility = .none }
        effective.nightPalette?.labelDensity = settings.labelDensity
        let key = "\(effective.hashValue)-\(nightActive)"
        guard key != styleKey else { return }
        styleKey = key
        let style = VectorStyleBuilder.style(for: effective, nightActive: nightActive, configuration: tiles)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oxyde-style-\(abs(key.hashValue)).json")
        do {
            try style.data().write(to: url, options: .atomic)
            styleLoaded = false
            mapView.styleURL = url
        } catch {
            assertionFailure("Could not write style: \(error)")
        }
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        styleLoaded = true
        pushRoutes()
        pushIncidents()
    }

    func setRoutes(_ routes: [Route], selectedID: UUID?, traveledDistance: Double?) {
        self.routes = routes
        selectedRouteID = selectedID
        traveled = traveledDistance
        pushRoutes()
    }

    private func pushRoutes() {
        guard styleLoaded, let source = mapView.style?.source(withIdentifier: VectorStyleBuilder.routeSourceID) as? MLNShapeSource else { return }
        let selected = routes.first { $0.id == selectedRouteID } ?? routes.first
        var remaining: [Coordinate] = selected?.coordinates ?? []
        var traveledPart: [Coordinate] = []
        if let selected, let traveled, traveled > 0 {
            let split = MeasuredPolyline(selected.coordinates).split(atDistance: traveled)
            remaining = split.remaining
            traveledPart = split.traveled
        }
        let alternates = routes.filter { $0.id != selected?.id }.map(\.coordinates)
        let json = VectorStyleBuilder.routeGeoJSON(remaining: remaining, traveled: traveledPart, alternates: alternates)
        if let data = try? json.data(), let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) {
            source.shape = shape
        }
    }

    func setIncidents(_ incidents: [Incident]) {
        self.incidents = incidents
        pushIncidents()
    }

    private func pushIncidents() {
        guard styleLoaded, let source = mapView.style?.source(withIdentifier: VectorStyleBuilder.incidentSourceID) as? MLNShapeSource else { return }
        let features = incidents.map { inc -> MLNPointFeature in
            let f = MLNPointFeature()
            f.coordinate = inc.coordinate.cl
            f.attributes = ["id": inc.id, "kind": inc.kind.rawValue]
            return f
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    func setPlaces(_ places: [Place], selectedID: String?) {
        mapView.removeAnnotations(Array(placeAnnotations.keys))
        placeAnnotations = [:]
        for p in places {
            let a = MLNPointAnnotation()
            a.coordinate = p.coordinate.cl
            a.title = p.name
            a.subtitle = p.address
            placeAnnotations[a] = p
        }
        mapView.addAnnotations(Array(placeAnnotations.keys))
    }

    func setDestinations(_ waypoints: [Waypoint]) {
        mapView.removeAnnotations(waypointAnnotations)
        waypointAnnotations = waypoints.map {
            let a = MLNPointAnnotation()
            a.coordinate = $0.coordinate.cl
            a.title = $0.name
            return a
        }
        mapView.addAnnotations(waypointAnnotations)
    }

    func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
        if let a = annotation as? MLNPointAnnotation, let p = placeAnnotations[a] { onSelectPlace?(p) }
    }

    func setVehicle(_ coordinate: Coordinate?, bearing: Double?) {
        // MapLibre's own user-location puck follows the device; the snapped position
        // drives the camera instead.
        mapView.showsUserHeadingIndicator = coordinate != nil
    }

    func follow(_ coordinate: Coordinate, bearing: Double, speed: Double, animated: Bool) {
        let distance = followDistance(theme: theme, settings: settings, speed: speed)
        let camera = MLNMapCamera(lookingAtCenter: coordinate.cl, acrossDistance: distance,
                                  pitch: CGFloat(followPitch(theme: theme, settings: settings)),
                                  heading: settings.cameraMode == .northUp ? 0 : bearing)
        mapView.setCamera(camera, withDuration: animated ? 0.9 : 0,
                          animationTimingFunction: CAMediaTimingFunction(name: .linear))
    }

    func showOverview(of coordinates: [Coordinate], edgePadding: UIEdgeInsets, animated: Bool) {
        guard let box = BoundingBox(coordinates: coordinates) else { return }
        let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: box.minLatitude, longitude: box.minLongitude),
                                         ne: CLLocationCoordinate2D(latitude: box.maxLatitude, longitude: box.maxLongitude))
        mapView.setVisibleCoordinateBounds(bounds, edgePadding: edgePadding, animated: animated, completionHandler: nil)
    }

    func center(on coordinate: Coordinate, distance: Double?, animated: Bool) {
        mapView.setCenter(coordinate.cl, animated: animated)
    }

    func zoom(by factor: Double) {
        mapView.setZoomLevel(mapView.zoomLevel - log2(factor), animated: true)
    }

    func resetNorth() { mapView.resetNorth() }

    func pan(by offset: CGPoint) {
        let p = CGPoint(x: mapView.bounds.midX + offset.x, y: mapView.bounds.midY + offset.y)
        mapView.setCenter(mapView.convert(p, toCoordinateFrom: mapView), animated: true)
        onUserGesture?()
    }

    func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
        if reason.contains(.gesturePan) || reason.contains(.gesturePinch) || reason.contains(.gestureRotate) {
            onUserGesture?()
        }
    }

    func mapViewRegionIsChanging(_ mapView: MLNMapView) {
        onCameraHeadingChange?(mapView.direction)
    }

    @objc private func longPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        onLongPress?(Coordinate(mapView.convert(g.location(in: mapView), toCoordinateFrom: mapView)))
    }
}
#endif
