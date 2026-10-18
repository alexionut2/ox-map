import Foundation
import CoreLocation
import Observation
import Network
import OxydeCore

extension Coordinate {
    init(_ c: CLLocationCoordinate2D) { self.init(latitude: c.latitude, longitude: c.longitude) }
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension LocationFix {
    init(_ l: CLLocation) {
        self.init(coordinate: Coordinate(l.coordinate), horizontalAccuracy: l.horizontalAccuracy, speed: l.speed,
                  speedAccuracy: l.speedAccuracy, course: l.course, timestamp: l.timestamp)
    }
}

/// Wraps CLLocationManager with three power modes. Background updates are switched on
/// only during active navigation, which is what the location background mode is for.
@MainActor
@Observable
final class LocationManager: NSObject {
    enum Mode { case off, browsing, navigating }

    enum Permission: Equatable {
        case notDetermined, denied, restricted, whenInUse, always
        var isAuthorized: Bool { self == .whenInUse || self == .always }
    }

    private(set) var permission: Permission = .notDetermined
    private(set) var isPreciseAccuracy = true
    private(set) var lastFix: LocationFix?
    /// Compass heading in degrees, used for the browsing map only.
    private(set) var heading: Double?
    private(set) var lastError: String?
    private(set) var mode: Mode = .off

    /// Called for every accepted fix (navigation subscribes to this).
    @ObservationIgnored var onFix: ((LocationFix) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        updatePermission(manager.authorizationStatus)
    }

    var hasBackgroundMode: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") ?? false
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// Navigation needs precise location; with reduced accuracy, ask for a temporary
    /// full-accuracy grant using the purpose string in Info.plist.
    func requestTemporaryPreciseAccuracy() async {
        guard !isPreciseAccuracy else { return }
        try? await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "Navigation")
        isPreciseAccuracy = manager.accuracyAuthorization == .fullAccuracy
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        guard permission.isAuthorized else { return }
        switch newMode {
        case .off:
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
            manager.allowsBackgroundLocationUpdates = false
        case .browsing:
            manager.allowsBackgroundLocationUpdates = false
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 10
            manager.activityType = .automotiveNavigation
            manager.pausesLocationUpdatesAutomatically = true
            manager.startUpdatingLocation()
            manager.headingFilter = 5
            manager.startUpdatingHeading()
        case .navigating:
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
            manager.activityType = .automotiveNavigation
            manager.pausesLocationUpdatesAutomatically = false
            if hasBackgroundMode {
                manager.allowsBackgroundLocationUpdates = true
                manager.showsBackgroundLocationIndicator = true
            }
            manager.stopUpdatingHeading()
            manager.startUpdatingLocation()
        }
    }

    private func updatePermission(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: permission = .notDetermined
        case .denied: permission = .denied
        case .restricted: permission = .restricted
        case .authorizedWhenInUse: permission = .whenInUse
        case .authorizedAlways: permission = .always
        @unknown default: permission = .denied
        }
        isPreciseAccuracy = manager.accuracyAuthorization == .fullAccuracy
        if permission.isAuthorized, mode != .off { setMode(mode) }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.updatePermission(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.filter { $0.horizontalAccuracy >= 0 }.map(LocationFix.init)
        Task { @MainActor in
            for fix in fixes {
                // Drop fixes older than ones we already have (deferred deliveries).
                if let last = self.lastFix, fix.timestamp < last.timestamp { continue }
                self.lastFix = fix
                self.lastError = nil
                self.onFix?(fix)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = h }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message: String?
        if let e = error as? CLError, e.code == .locationUnknown {
            message = nil // Transient; Core Location keeps trying.
        } else {
            message = error.localizedDescription
        }
        Task { @MainActor in self.lastError = message }
    }
}

/// Network reachability, so the UI can say "offline" instead of failing silently.
@MainActor
@Observable
final class Reachability {
    private(set) var isOnline = true
    private(set) var isExpensive = false
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                self?.isOnline = online
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "oxyde.reachability"))
    }
}
