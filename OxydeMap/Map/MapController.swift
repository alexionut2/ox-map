import UIKit
import OxydeCore

enum MapSurface {
    case phone, carPlay, preview
}

/// The rendering boundary. The rest of the app talks to this protocol, so the MapKit
/// and vector (MapLibre) engines are interchangeable and routing, search and guidance
/// never depend on how the map is drawn.
@MainActor
protocol MapController: AnyObject {
    var view: UIView { get }
    var surface: MapSurface { get }

    /// Long-press on the map (drop a pin / navigate to a point).
    var onLongPress: ((Coordinate) -> Void)? { get set }
    var onSelectPlace: ((Place) -> Void)? { get set }
    var onSelectIncident: ((Incident) -> Void)? { get set }
    /// The user panned or zoomed, so automatic following should pause.
    var onUserGesture: (() -> Void)? { get set }
    var onCameraHeadingChange: ((Double) -> Void)? { get set }

    func apply(theme: MapTheme, nightActive: Bool, settings: AppSettings)
    func setRoutes(_ routes: [Route], selectedID: UUID?, traveledDistance: Double?)
    func setIncidents(_ incidents: [Incident])
    func setPlaces(_ places: [Place], selectedID: String?)
    func setDestinations(_ waypoints: [Waypoint])
    /// Explorer mode squares, as closed rings.
    func setExplored(_ polygons: [[Coordinate]])
    /// Friends in the convoy (never includes the driver).
    func setConvoy(_ members: [ConvoyMember])
    /// Shows the navigation puck at a snapped position; `nil` returns to the system dot.
    func setVehicle(_ coordinate: Coordinate?, bearing: Double?)
    /// Moves the navigation camera to follow the vehicle.
    func follow(_ coordinate: Coordinate, bearing: Double, speed: Double, animated: Bool)
    func showOverview(of coordinates: [Coordinate], edgePadding: UIEdgeInsets, animated: Bool)
    func center(on coordinate: Coordinate, distance: Double?, animated: Bool)
    func zoom(by factor: Double)
    func resetNorth()
    func pan(by offset: CGPoint)
}

enum MapControllerFactory {
    @MainActor
    static func make(engine: MapEngine, surface: MapSurface, configuration: AppConfiguration) -> MapController {
        #if canImport(MapLibre)
        if engine == .vector, let tiles = configuration.vectorTiles, tiles.isComplete {
            return VectorMapController(surface: surface, tiles: tiles)
        }
        #endif
        return MapKitMapController(surface: surface)
    }
}

extension MapController {
    /// Camera distance for following: the theme's distance, the user's zoom preference,
    /// and pulled back at speed so the driver sees further ahead.
    func followDistance(theme: MapTheme, settings: AppSettings, speed: Double) -> Double {
        let speedFactor = 1 + min(1.5, max(0, speed) / 30)
        return theme.camera.distance * settings.zoomScale * speedFactor
    }

    func followPitch(theme: MapTheme, settings: AppSettings) -> Double {
        switch settings.cameraMode {
        case .northUp: return 0
        case .headingUp: return min(45, theme.camera.pitch * 0.6)
        case .perspective3D: return max(45, theme.camera.pitch)
        }
    }
}
