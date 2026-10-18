import Foundation

/// Things that earn experience. None of them reward speed, short travel times or
/// aggressive driving: XP comes from distance, exploring, arriving and helping others.
public enum ProgressEvent: Equatable, Sendable {
    case drove(meters: Double, atNight: Bool)
    case arrived
    case exploredCell
    case reportShared
    case convoyJoined
    case themeApplied(id: String)
}

public struct Achievement: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    /// SF Symbol name.
    public var symbol: String
    public var xp: Int
}

/// The driver's level, XP and badges, kept on the device.
public struct DriverProgress: Codable, Equatable, Sendable {
    public private(set) var xp: Int = 0
    public private(set) var metersDriven: Double = 0
    public private(set) var nightMeters: Double = 0
    public private(set) var arrivals: Int = 0
    public private(set) var cellsExplored: Int = 0
    public private(set) var reportsShared: Int = 0
    public private(set) var convoys: Int = 0
    public private(set) var themesTried: Set<String> = []
    public private(set) var unlocked: Set<String> = []
    /// Distance not yet converted into XP, so short hops still add up.
    var pendingMeters: Double = 0

    public init() {}

    public static let achievements: [Achievement] = [
        Achievement(id: "first-arrival", title: "First Destination", detail: "Arrive at a destination with guidance.", symbol: "flag.checkered", xp: 50),
        Achievement(id: "km-100", title: "Road Tripper", detail: "Drive 100 km with Oxyde Map.", symbol: "road.lanes", xp: 100),
        Achievement(id: "km-1000", title: "Long Hauler", detail: "Drive 1,000 km with Oxyde Map.", symbol: "infinity", xp: 300),
        Achievement(id: "night-50", title: "Night Owl", detail: "Drive 50 km after sunset.", symbol: "moon.stars.fill", xp: 100),
        Achievement(id: "explorer-25", title: "Scout", detail: "Reveal 25 squares in Explorer mode.", symbol: "map", xp: 75),
        Achievement(id: "explorer-250", title: "Cartographer", detail: "Reveal 250 squares in Explorer mode.", symbol: "globe.europe.africa.fill", xp: 250),
        Achievement(id: "reporter", title: "Road Helper", detail: "Share your first road report.", symbol: "exclamationmark.bubble.fill", xp: 50),
        Achievement(id: "reporter-25", title: "Community Guardian", detail: "Share 25 road reports.", symbol: "shield.lefthalf.filled", xp: 200),
        Achievement(id: "convoy", title: "Convoy Crew", detail: "Drive in a convoy with friends.", symbol: "car.2.fill", xp: 75),
        Achievement(id: "stylist", title: "Map Stylist", detail: "Try 5 different map styles.", symbol: "paintpalette.fill", xp: 50),
        Achievement(id: "arrivals-50", title: "Regular", detail: "Arrive at 50 destinations.", symbol: "mappin.and.ellipse", xp: 200),
    ]

    public static let ranks = ["Rookie", "Navigator", "Road Captain", "Pathfinder", "Trailblazer", "Road Legend"]

    /// XP needed to reach `level` (level 1 starts at 0): 0, 100, 300, 600, 1000…
    public static func threshold(forLevel level: Int) -> Int { 50 * level * (level - 1) }

    public var level: Int {
        var l = 1
        while Self.threshold(forLevel: l + 1) <= xp { l += 1 }
        return l
    }

    /// 0…1 progress through the current level.
    public var levelProgress: Double {
        let lo = Self.threshold(forLevel: level), hi = Self.threshold(forLevel: level + 1)
        return Double(xp - lo) / Double(hi - lo)
    }

    public var rank: String { Self.ranks[min(Self.ranks.count - 1, (level - 1) / 5)] }

    public func isUnlocked(_ a: Achievement) -> Bool { unlocked.contains(a.id) }

    /// Applies an event and returns any achievements it unlocked, for a celebration.
    @discardableResult
    public mutating func apply(_ event: ProgressEvent) -> [Achievement] {
        switch event {
        case let .drove(meters, atNight):
            guard meters.isFinite, meters > 0, meters < 5_000 else { return [] }
            metersDriven += meters
            if atNight { nightMeters += meters }
            pendingMeters += meters
            let whole = Int(pendingMeters / 100)
            xp += whole
            pendingMeters -= Double(whole) * 100
        case .arrived:
            arrivals += 1; xp += 25
        case .exploredCell:
            cellsExplored += 1; xp += 15
        case .reportShared:
            reportsShared += 1; xp += 20
        case .convoyJoined:
            convoys += 1; xp += 30
        case .themeApplied(let id):
            if themesTried.insert(id).inserted { xp += 10 }
        }
        return checkAchievements()
    }

    mutating func checkAchievements() -> [Achievement] {
        let earned: [String: Bool] = [
            "first-arrival": arrivals >= 1, "arrivals-50": arrivals >= 50,
            "km-100": metersDriven >= 100_000, "km-1000": metersDriven >= 1_000_000,
            "night-50": nightMeters >= 50_000,
            "explorer-25": cellsExplored >= 25, "explorer-250": cellsExplored >= 250,
            "reporter": reportsShared >= 1, "reporter-25": reportsShared >= 25,
            "convoy": convoys >= 1, "stylist": themesTried.count >= 5,
        ]
        var new: [Achievement] = []
        for a in Self.achievements where earned[a.id] == true && !unlocked.contains(a.id) {
            unlocked.insert(a.id)
            xp += a.xp
            new.append(a)
        }
        return new
    }

    public mutating func reset() { self = DriverProgress() }
}
