#if canImport(MapLibre)
import MapLibre
import UIKit
import OxydeCore

/// Point annotations Oxyde adds on top of the vector map.
final class VehiclePointAnnotation: MLNPointAnnotation {}
final class ConvoyPointAnnotation: MLNPointAnnotation {
    var member: ConvoyMember?
}

/// Writes compiled style documents to temporary files for MapLibre to load.
enum VectorStyleFile {
    /// Hash values change between launches, so file names carry a per-launch prefix.
    private static let launch = UUID().uuidString.prefix(8)

    @MainActor
    static func url(for theme: MapTheme, nightActive: Bool, tiles: VectorTileConfiguration) throws -> URL {
        let key = "\(theme.hashValue)-\(nightActive)-\(tiles.hashValue)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oxyde-style-\(launch)-\(abs(key.hashValue % 1_000_000_000)).json")
        if !FileManager.default.fileExists(atPath: url.path) {
            let style = VectorStyleBuilder.style(for: theme, nightActive: nightActive, configuration: tiles)
            try style.data().write(to: url, options: .atomic)
        }
        return url
    }
}

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
    private var explored: [[Coordinate]] = []
    private var convoyAnnotations: [ConvoyPointAnnotation] = []
    private var vehicleAnnotation: VehiclePointAnnotation?
    private var vehicleBearing: Double = 0

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
        refreshVehicleView()
        let key = "\(effective.hashValue)-\(nightActive)"
        guard key != styleKey else { return }
        styleKey = key
        do {
            let url = try VectorStyleFile.url(for: effective, nightActive: nightActive, tiles: tiles)
            styleLoaded = false
            if mapView.styleURL != nil, surface == .phone {
                // Cross-fade between map styles.
                UIView.transition(with: mapView, duration: 0.4, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                    self.mapView.styleURL = url
                }
            } else {
                mapView.styleURL = url
            }
        } catch {
            assertionFailure("Could not write style: \(error)")
        }
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        styleLoaded = true
        pushRoutes()
        pushIncidents()
        pushExplored()
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

    func setExplored(_ polygons: [[Coordinate]]) {
        explored = surface == .phone ? polygons : []
        pushExplored()
    }

    private func pushExplored() {
        guard styleLoaded, let source = mapView.style?.source(withIdentifier: VectorStyleBuilder.exploredSourceID) as? MLNShapeSource else { return }
        let json = VectorStyleBuilder.exploredGeoJSON(explored)
        if let data = try? json.data(), let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) {
            source.shape = shape
        }
    }

    func setConvoy(_ members: [ConvoyMember]) {
        mapView.removeAnnotations(convoyAnnotations)
        convoyAnnotations = members.compactMap { m in
            guard let c = m.coordinate else { return nil }
            let a = ConvoyPointAnnotation()
            a.member = m
            a.coordinate = c.cl
            a.title = m.name
            return a
        }
        mapView.addAnnotations(convoyAnnotations)
    }

    func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
        if annotation is VehiclePointAnnotation {
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "vehicle") ?? MLNAnnotationView(reuseIdentifier: "vehicle")
            v.frame = CGRect(origin: .zero, size: VehicleIconRenderer.size)
            v.layer.contents = vehicleImage().cgImage
            v.transform = CGAffineTransform(rotationAngle: CGFloat((vehicleBearing - mapView.direction) * .pi / 180))
            return v
        }
        if let a = annotation as? ConvoyPointAnnotation, let m = a.member {
            let v = MLNAnnotationView(reuseIdentifier: nil)
            v.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
            let color = UIColor(hex: HexColor(hex: m.color) ?? "#7C4DFF")
            v.layer.contents = UIGraphicsImageRenderer(size: v.frame.size).image { _ in
                color.setFill()
                UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 30, height: 30)).fill()
                UIColor.white.setStroke()
                let ring = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 30, height: 30)); ring.lineWidth = 2.5; ring.stroke()
                let text = String(m.name.prefix(1)).uppercased() as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: UIColor.white]
                let size = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: 17 - size.width / 2, y: 17 - size.height / 2), withAttributes: attrs)
            }.cgImage
            return v
        }
        return nil
    }

    private func vehicleImage() -> UIImage {
        VehicleIconRenderer.image(for: settings.vehicleIcon, tint: UIColor(hex: settings.accentOverride ?? theme.interface.accent))
    }

    private func refreshVehicleView() {
        guard let a = vehicleAnnotation, let v = mapView.view(for: a) else { return }
        v.layer.contents = vehicleImage().cgImage
        v.transform = CGAffineTransform(rotationAngle: CGFloat((vehicleBearing - mapView.direction) * .pi / 180))
    }

    func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
        if let a = annotation as? MLNPointAnnotation, let p = placeAnnotations[a] { onSelectPlace?(p) }
    }

    func setVehicle(_ coordinate: Coordinate?, bearing: Double?) {
        if let bearing { vehicleBearing = bearing }
        guard let coordinate else {
            if let a = vehicleAnnotation { mapView.removeAnnotation(a) }
            vehicleAnnotation = nil
            mapView.showsUserLocation = surface != .preview
            return
        }
        // While navigating, the snapped position with the chosen vehicle icon replaces
        // MapLibre's own location dot.
        mapView.showsUserLocation = false
        if let a = vehicleAnnotation {
            a.coordinate = coordinate.cl
            refreshVehicleView()
        } else {
            let a = VehiclePointAnnotation()
            a.coordinate = coordinate.cl
            vehicleAnnotation = a
            mapView.addAnnotation(a)
        }
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
        refreshVehicleView()
        onCameraHeadingChange?(mapView.direction)
    }

    @objc private func longPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        onLongPress?(Coordinate(mapView.convert(g.location(in: mapView), toCoordinateFrom: mapView)))
    }
}
/// Renders Studio thumbnails of vector themes with the real tiles and style.
enum VectorSnapshot {
    @MainActor
    static func image(for theme: MapTheme, nightActive: Bool, center: Coordinate, size: CGSize,
                      tiles: VectorTileConfiguration) async -> UIImage? {
        guard let url = try? VectorStyleFile.url(for: theme, nightActive: nightActive, tiles: tiles) else { return nil }
        let camera = MLNMapCamera(lookingAtCenter: center.cl, acrossDistance: 2200,
                                  pitch: CGFloat(min(theme.camera.pitch, 55)), heading: 0)
        let options = MLNMapSnapshotOptions(styleURL: url, camera: camera, size: size)
        let snapshotter = MLNMapSnapshotter(options: options)
        return await withCheckedContinuation { cont in
            snapshotter.start { snapshot, _ in
                _ = snapshotter // Keep the snapshotter alive until it finishes.
                cont.resume(returning: snapshot?.image)
            }
        }
    }
}
#endif
