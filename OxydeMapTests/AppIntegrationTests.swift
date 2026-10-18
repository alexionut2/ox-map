import XCTest
import MapKit
@testable import OxydeMap
import OxydeCore

/// App-target tests that need iOS frameworks. Pure logic is covered by OxydeCoreTests.
@MainActor
final class AppIntegrationTests: XCTestCase {
    func testPolylineCoordinatesRoundTrip() {
        let points = [CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35),
                      CLLocationCoordinate2D(latitude: 48.86, longitude: 2.36),
                      CLLocationCoordinate2D(latitude: 48.87, longitude: 2.34)]
        let line = MKPolyline(coordinates: points, count: points.count)
        let coords = line.coordinates
        XCTAssertEqual(coords.count, 3)
        XCTAssertEqual(coords[1].latitude, 48.86, accuracy: 1e-9)
        XCTAssertEqual(coords[2].longitude, 2.34, accuracy: 1e-9)
    }

    func testMapItemConversionKeepsNameAndCoordinate() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405)))
        item.name = "Brandenburg Gate"
        let place = MapKitSearchService.place(from: item)
        XCTAssertEqual(place.name, "Brandenburg Gate")
        XCTAssertEqual(place.coordinate.latitude, 52.52, accuracy: 1e-9)
        XCTAssertEqual(place.provider, "Apple Maps")
    }

    func testQuickSearchCategoriesMapToMapKit() {
        // Car wash has no MapKit category and is searched by text instead.
        for c in PlaceCategory.allCases where c != .carWash && c != .other {
            XCTAssertFalse(c.mapKitCategories.isEmpty, "\(c) has no MapKit category")
            XCTAssertEqual(PlaceCategory(mapKit: c.mapKitCategories[0]), c)
        }
    }

    func testWaypointMapItem() {
        let w = Waypoint(name: "Office", coordinate: Coordinate(latitude: 40.0, longitude: -74.0))
        XCTAssertEqual(w.mapItem.name, "Office")
        XCTAssertEqual(w.mapItem.placemark.coordinate.longitude, -74.0, accuracy: 1e-9)
    }

    func testSettingsStorePersistsChanges() {
        let suite = "oxyde.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.value.hapticsEnabled = false
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.value.hapticsEnabled)
    }

    func testConfigurationTreatsUnexpandedValuesAsMissing() {
        // The test host's Info.plist has OXBackendBaseURL = $(OX_BACKEND_BASE_URL) expanded
        // to empty unless a Secrets.xcconfig defines it; either way it must not be "$(".
        let config = AppConfiguration.current
        if let url = config.backendBaseURL { XCTAssertFalse(url.absoluteString.hasPrefix("$(")) }
    }

    func testRoutingCapabilitiesAreHonest() {
        let caps = MapKitRoutingService().capabilities
        XCTAssertFalse(caps.providesLaneGuidance)
        XCTAssertFalse(caps.providesSpeedLimits)
        XCTAssertFalse(caps.supportsAvoidFerries)
    }
}
