import Foundation
import Observation
import OxydeCore

/// Explorer mode, XP and achievements. Everything stays in the app's own files on this
/// device; nothing here is uploaded.
@MainActor
@Observable
final class PlayStore {
    struct Celebration: Identifiable, Equatable {
        enum Kind { case achievement, levelUp, arrival }
        let id = UUID()
        let kind: Kind
        let title: String
        let subtitle: String
        let symbol: String
    }

    private(set) var grid: ExplorationGrid
    private(set) var progress: DriverProgress
    /// The latest thing worth celebrating; the map shows it with confetti.
    var celebration: Celebration?
    /// Bumped whenever new squares are revealed, so maps redraw the explored layer.
    private(set) var exploredRevision = 0

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var lastFix: LocationFix?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let directory: URL

    init(settings: SettingsStore) {
        self.settings = settings
        directory = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                     ?? FileManager.default.temporaryDirectory).appendingPathComponent("Play", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        grid = Self.load(ExplorationGrid.self, from: directory.appendingPathComponent("exploration.json")) ?? ExplorationGrid()
        progress = Self.load(DriverProgress.self, from: directory.appendingPathComponent("progress.json")) ?? DriverProgress()
        if ProcessInfo.processInfo.arguments.contains("-uiTestingReset") {
            grid = ExplorationGrid()
            progress = DriverProgress()
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Input

    func handle(_ fix: LocationFix, nightActive: Bool) {
        let s = settings.value
        defer { lastFix = fix }
        if s.explorerEnabled, grid.record(fix.coordinate, accuracy: fix.horizontalAccuracy) {
            exploredRevision += 1
            record(.exploredCell)
            scheduleSave()
        }
        guard s.progressEnabled, let last = lastFix,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 50 else { return }
        let dt = fix.timestamp.timeIntervalSince(last.timestamp)
        // Count distance only while actually moving like a vehicle, between close fixes.
        guard dt > 0, dt < 30 else { return }
        let meters = GeoMath.distance(last.coordinate, fix.coordinate)
        guard meters / dt > 2, meters / dt < 90 else { return }
        record(.drove(meters: meters, atNight: nightActive))
    }

    func record(_ event: ProgressEvent) {
        guard settings.value.progressEnabled else { return }
        let levelBefore = progress.level
        let unlocked = progress.apply(event)
        if let a = unlocked.last {
            celebration = Celebration(kind: .achievement, title: a.title, subtitle: a.detail, symbol: a.symbol)
        } else if progress.level > levelBefore {
            celebration = Celebration(kind: .levelUp, title: "Level \(progress.level)",
                                      subtitle: "You're now a \(progress.rank).", symbol: "star.fill")
        } else if event == .arrived {
            celebration = Celebration(kind: .arrival, title: "You've arrived", subtitle: "+25 XP", symbol: "flag.checkered")
        }
        scheduleSave()
    }

    // MARK: Map

    @ObservationIgnored private var nearCache: (key: String, polygons: [[Coordinate]])?

    /// Explored squares within roughly 25 km of a point, cached until something changes.
    func exploredNear(_ c: Coordinate?) -> [[Coordinate]] {
        guard settings.value.explorerEnabled, let c else { return [] }
        let key = "\(exploredRevision)-\(Int(c.latitude * 10))-\(Int(c.longitude * 10))"
        if let nearCache, nearCache.key == key { return nearCache.polygons }
        let area = BoundingBox(minLatitude: c.latitude - 0.25, minLongitude: c.longitude - 0.35,
                               maxLatitude: c.latitude + 0.25, maxLongitude: c.longitude + 0.35)
        let polygons = grid.cells(in: area).map(ExplorationGrid.corners(of:))
        nearCache = (key, polygons)
        return polygons
    }

    // MARK: Privacy controls

    func eraseExploration() {
        grid.erase()
        exploredRevision += 1
        scheduleSave()
    }

    func resetProgress() {
        progress.reset()
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let grid = grid, progress = progress, dir = directory
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            let enc = JSONEncoder()
            try? enc.encode(grid).write(to: dir.appendingPathComponent("exploration.json"), options: [.atomic, .completeFileProtection])
            try? enc.encode(progress).write(to: dir.appendingPathComponent("progress.json"), options: [.atomic, .completeFileProtection])
        }
    }
}
