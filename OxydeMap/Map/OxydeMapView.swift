import SwiftUI
import MapKit
import OxydeCore

/// Lets SwiftUI views send imperative commands (zoom, recenter, overview) to the map.
@MainActor
final class MapHandle {
    fileprivate(set) var controller: MapController?
    init() {}
}

/// Everything the map should currently show. SwiftUI rebuilds this value; the
/// representable diffs it into calls on the `MapController`.
struct MapSceneState: Equatable {
    var theme: MapTheme
    var nightActive: Bool
    var settings: AppSettings
    var routes: [Route] = []
    var selectedRouteID: UUID?
    var traveledDistance: Double?
    var incidents: [Incident] = []
    var places: [Place] = []
    var selectedPlaceID: String?
    var waypoints: [Waypoint] = []
    var explored: [[Coordinate]] = []
    var convoy: [ConvoyMember] = []
    var vehicle: Coordinate?
    var vehicleBearing: Double?
    var vehicleSpeed: Double = 0
    var isFollowing = false
    /// Fixed framing for preview maps (Studio, theme editor).
    var cameraCenter: Coordinate?
}

struct OxydeMapView: UIViewRepresentable {
    var engine: MapEngine
    var surface: MapSurface = .phone
    var state: MapSceneState
    var handle: MapHandle?
    var onLongPress: ((Coordinate) -> Void)?
    var onSelectPlace: ((Place) -> Void)?
    var onSelectIncident: ((Incident) -> Void)?
    var onUserGesture: (() -> Void)?
    var onHeadingChange: ((Double) -> Void)?

    final class Coordinator {
        var controller: MapController
        var last: MapSceneState?
        init(controller: MapController) { self.controller = controller }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: MapControllerFactory.make(engine: engine, surface: surface, configuration: .current))
    }

    func makeUIView(context: Context) -> UIView {
        let c = context.coordinator.controller
        handle?.controller = c
        return c.view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let c = context.coordinator.controller
        c.onLongPress = onLongPress
        c.onSelectPlace = onSelectPlace
        c.onSelectIncident = onSelectIncident
        c.onUserGesture = onUserGesture
        c.onCameraHeadingChange = onHeadingChange
        let old = context.coordinator.last
        let s = state
        if old?.theme != s.theme || old?.nightActive != s.nightActive || old?.settings != s.settings {
            c.apply(theme: s.theme, nightActive: s.nightActive, settings: s.settings)
        }
        if old?.routes.map(\.id) != s.routes.map(\.id) || old?.selectedRouteID != s.selectedRouteID
            || old?.traveledDistance != s.traveledDistance {
            c.setRoutes(s.routes, selectedID: s.selectedRouteID, traveledDistance: s.traveledDistance)
        }
        if old?.incidents != s.incidents { c.setIncidents(s.incidents) }
        if old?.places != s.places || old?.selectedPlaceID != s.selectedPlaceID {
            c.setPlaces(s.places, selectedID: s.selectedPlaceID)
        }
        if old?.waypoints != s.waypoints { c.setDestinations(s.waypoints) }
        if old?.explored != s.explored { c.setExplored(s.explored) }
        if old?.convoy != s.convoy { c.setConvoy(s.convoy) }
        if old?.vehicle != s.vehicle || old?.vehicleBearing != s.vehicleBearing {
            c.setVehicle(s.vehicle, bearing: s.vehicleBearing)
            if s.isFollowing, let v = s.vehicle {
                c.follow(v, bearing: s.vehicleBearing ?? 0, speed: s.vehicleSpeed, animated: old?.vehicle != nil)
            }
        } else if s.isFollowing, old?.isFollowing == false, let v = s.vehicle {
            c.follow(v, bearing: s.vehicleBearing ?? 0, speed: s.vehicleSpeed, animated: true)
        }
        if let center = s.cameraCenter, old?.cameraCenter != center {
            c.center(on: center, distance: 1800, animated: false)
        }
        context.coordinator.last = s
    }
}

/// Renders a still image of a theme with MapKit's snapshotter, for Studio thumbnails.
/// It is the real map in that configuration, not an illustration.
@MainActor
final class ThemeSnapshotCache {
    static let shared = ThemeSnapshotCache()
    private var cache: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// Snapshots run one at a time so a long gallery doesn't load dozens of maps at once.
    private var queue: Task<Void, Never>?

    func image(for theme: MapTheme, engine: MapEngine, nightActive: Bool, center: Coordinate, size: CGSize) async -> UIImage? {
        let key = "\(theme.id)-\(theme.hashValue)-\(engine)-\(nightActive)-\(Int(center.latitude * 100))-\(Int(center.longitude * 100))"
        if let img = cache[key] { return img }
        if let task = inFlight[key] { return await task.value }
        let previous = queue
        let task = Task<UIImage?, Never> {
            await previous?.value
            #if canImport(MapLibre)
            if engine == .vector, let tiles = AppConfiguration.current.vectorTiles {
                return await VectorSnapshot.image(for: theme, nightActive: nightActive, center: center, size: size, tiles: tiles)
            }
            #endif
            let options = MKMapSnapshotter.Options()
            options.preferredConfiguration = MapKitMapController.configuration(for: theme, poi: theme.poiVisibility,
                                                                               traffic: theme.showsTraffic)
            options.camera = MKMapCamera(lookingAtCenter: center.cl, fromDistance: 2200,
                                         pitch: CGFloat(min(theme.camera.pitch, 60)), heading: 0)
            options.size = size
            options.traitCollection = UITraitCollection(userInterfaceStyle: theme.isDark(nightActive: nightActive) ? .dark : .light)
            guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
            return snapshot.image
        }
        inFlight[key] = task
        queue = Task { _ = await task.value }
        let img = await task.value
        inFlight[key] = nil
        if let img { cache[key] = img }
        return img
    }
}
