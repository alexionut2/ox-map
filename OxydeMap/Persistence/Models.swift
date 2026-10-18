import Foundation
import SwiftData
import OxydeCore

enum SavedPlaceKind: String, Codable, CaseIterable {
    case home, work, favorite
}

@Model
final class SavedPlace {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var categoryRaw: String?
    var collection: String?
    var createdAt: Date

    init(name: String, kind: SavedPlaceKind, coordinate: Coordinate, address: String?, category: PlaceCategory?, collection: String? = nil) {
        id = UUID()
        self.name = name
        kindRaw = kind.rawValue
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.address = address
        categoryRaw = category?.rawValue
        self.collection = collection
        createdAt = Date()
    }

    var kind: SavedPlaceKind { SavedPlaceKind(rawValue: kindRaw) ?? .favorite }
    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    var place: Place {
        Place(id: id.uuidString, name: name, coordinate: coordinate, address: address,
              category: categoryRaw.flatMap(PlaceCategory.init(rawValue:)), provider: "Saved")
    }
}

@Model
final class RecentDestination {
    @Attribute(.unique) var key: String
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var lastUsed: Date
    var useCount: Int

    init(place: Place) {
        key = Place.syntheticID(name: place.name, coordinate: place.coordinate)
        name = place.name
        latitude = place.coordinate.latitude
        longitude = place.coordinate.longitude
        address = place.address
        lastUsed = Date()
        useCount = 1
    }

    var place: Place {
        Place(id: key, name: name, coordinate: Coordinate(latitude: latitude, longitude: longitude), address: address, provider: "Recent")
    }
}

@Model
final class SavedRoute {
    @Attribute(.unique) var id: UUID
    var name: String
    /// JSON-encoded `[Waypoint]` (the stops, not including the start).
    var stopsData: Data
    var avoidTolls: Bool
    var avoidHighways: Bool
    var createdAt: Date
    var lastUsed: Date?

    init(name: String, stops: [Waypoint], preferences: RoutePreferences) {
        id = UUID()
        self.name = name
        stopsData = (try? JSONEncoder().encode(stops)) ?? Data()
        avoidTolls = preferences.avoidTolls
        avoidHighways = preferences.avoidHighways
        createdAt = Date()
    }

    var stops: [Waypoint] { (try? JSONDecoder().decode([Waypoint].self, from: stopsData)) ?? [] }
    var preferences: RoutePreferences { RoutePreferences(avoidTolls: avoidTolls, avoidHighways: avoidHighways) }
}

/// One recorded trip. Created only when trip history is turned on.
@Model
final class TripRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var distance: Double
    var duration: Double
    var movingDuration: Double
    var averageMovingSpeed: Double?
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var encodedShape: String?
    var destinationName: String?
    var note: String?

    init(summary: TripSummary) {
        id = UUID()
        startedAt = summary.startedAt
        endedAt = summary.endedAt
        distance = summary.distance
        duration = summary.duration
        movingDuration = summary.movingDuration
        averageMovingSpeed = summary.averageMovingSpeed
        startLatitude = summary.start?.latitude
        startLongitude = summary.start?.longitude
        endLatitude = summary.end?.latitude
        endLongitude = summary.end?.longitude
        encodedShape = summary.encodedShape
        destinationName = summary.destinationName
    }

    var shape: [Coordinate] { encodedShape.flatMap { PolylineCodec.decode($0) } ?? [] }
    var start: Coordinate? { startLatitude.flatMap { lat in startLongitude.map { Coordinate(latitude: lat, longitude: $0) } } }
    var end: Coordinate? { endLatitude.flatMap { lat in endLongitude.map { Coordinate(latitude: lat, longitude: $0) } } }
}

@MainActor
final class PersistenceController {
    let container: ModelContainer

    init() {
        let schema = Schema([SavedPlace.self, RecentDestination.self, SavedRoute.self, TripRecord.self])
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTestingReset")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A damaged store must not stop navigation from working: fall back to memory.
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
    }

    var context: ModelContext { container.mainContext }

    func recordRecent(_ place: Place) {
        let key = Place.syntheticID(name: place.name, coordinate: place.coordinate)
        let d = FetchDescriptor<RecentDestination>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(d).first {
            existing.lastUsed = Date()
            existing.useCount += 1
        } else {
            context.insert(RecentDestination(place: place))
        }
        try? context.save()
    }

    func recents(limit: Int = 12) -> [RecentDestination] {
        var d = FetchDescriptor<RecentDestination>(sortBy: [SortDescriptor(\.lastUsed, order: .reverse)])
        d.fetchLimit = limit
        return (try? context.fetch(d)) ?? []
    }

    func savedPlaces() -> [SavedPlace] {
        (try? context.fetch(FetchDescriptor<SavedPlace>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func place(of kind: SavedPlaceKind) -> SavedPlace? {
        savedPlaces().first { $0.kind == kind }
    }

    /// Home and work are unique: saving a new one replaces the old.
    func save(_ place: Place, as kind: SavedPlaceKind) {
        if kind != .favorite, let old = self.place(of: kind) { context.delete(old) }
        context.insert(SavedPlace(name: kind == .favorite ? place.name : (kind == .home ? "Home" : "Work"),
                                  kind: kind, coordinate: place.coordinate, address: place.address ?? place.name,
                                  category: place.category))
        try? context.save()
    }

    func isFavorite(_ place: Place) -> Bool {
        savedPlaces().contains { $0.kind == .favorite && GeoMath.distance($0.coordinate, place.coordinate) < 15 }
    }

    func saveTrip(_ summary: TripSummary) {
        // Very short trips (a parking-lot test) are not worth keeping.
        guard summary.distance > 200 else { return }
        context.insert(TripRecord(summary: summary))
        try? context.save()
    }

    func deleteAllTrips() {
        try? context.delete(model: TripRecord.self)
        try? context.save()
    }

    func deleteAllData() {
        try? context.delete(model: TripRecord.self)
        try? context.delete(model: RecentDestination.self)
        try? context.delete(model: SavedRoute.self)
        try? context.delete(model: SavedPlace.self)
        try? context.save()
    }
}
