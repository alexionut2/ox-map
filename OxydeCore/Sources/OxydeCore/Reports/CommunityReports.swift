import Foundation

public enum ReportCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case accident, trafficJam, hazard, roadworks, closure, objectOnRoad, stoppedVehicle, police, speedCamera, other
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accident: return "Accident"
        case .trafficJam: return "Traffic jam"
        case .hazard: return "Road hazard"
        case .roadworks: return "Roadworks"
        case .closure: return "Road closure"
        case .objectOnRoad: return "Object on road"
        case .stoppedVehicle: return "Stopped vehicle"
        case .police: return "Police"
        case .speedCamera: return "Speed camera"
        case .other: return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .accident: return "car.side.rear.and.collision.and.car.side.front"
        case .trafficJam: return "car.2.fill"
        case .hazard: return "exclamationmark.triangle.fill"
        case .roadworks: return "cone.fill"
        case .closure: return "xmark.octagon.fill"
        case .objectOnRoad: return "shippingbox.fill"
        case .stoppedVehicle: return "car.side.fill"
        case .police: return "shield.lefthalf.filled"
        case .speedCamera: return "camera.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    /// How long a report stays visible without confirmations.
    public var baseLifetime: TimeInterval {
        switch self {
        case .accident: return 60 * 60
        case .trafficJam: return 30 * 60
        case .hazard: return 60 * 60
        case .roadworks: return 8 * 60 * 60
        case .closure: return 6 * 60 * 60
        case .objectOnRoad: return 30 * 60
        case .stoppedVehicle: return 30 * 60
        case .police: return 60 * 60
        case .speedCamera: return 2 * 60 * 60
        case .other: return 45 * 60
        }
    }

    /// Reports of the same kind within this distance are treated as the same incident.
    public var mergeRadius: Double {
        switch self {
        case .trafficJam: return 400
        case .roadworks, .closure: return 250
        default: return 150
        }
    }
}

/// Where police and camera reports are restricted. Several countries prohibit or limit
/// warnings about police checks or speed cameras while driving (for example Germany and
/// Switzerland ban speed-camera warnings; France restricts precise locations). This list
/// is a conservative default and must be reviewed by counsel for each market before release.
public struct ReportRegionPolicy: Codable, Hashable, Sendable {
    public var speedCameraBlockedRegions: Set<String>
    public var policeBlockedRegions: Set<String>

    public init(speedCameraBlockedRegions: Set<String>, policeBlockedRegions: Set<String>) {
        self.speedCameraBlockedRegions = speedCameraBlockedRegions
        self.policeBlockedRegions = policeBlockedRegions
    }

    public static let conservativeDefault = ReportRegionPolicy(
        speedCameraBlockedRegions: ["DE", "CH", "FR", "AT", "BE", "LU", "CY", "SK", "SI", "PL", "TR"],
        policeBlockedRegions: ["FR", "CH"])

    public func isAllowed(_ category: ReportCategory, regionCode: String?) -> Bool {
        guard let region = regionCode?.uppercased() else {
            // Unknown region: stay conservative for restricted categories.
            return category != .speedCamera && category != .police
        }
        switch category {
        case .speedCamera: return !speedCameraBlockedRegions.contains(region)
        case .police: return !policeBlockedRegions.contains(region)
        default: return true
        }
    }

    public func allowedCategories(regionCode: String?) -> [ReportCategory] {
        ReportCategory.allCases.filter { isAllowed($0, regionCode: regionCode) }
    }
}

/// A driver-submitted report as returned by the Oxyde backend.
public struct CommunityReport: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var category: ReportCategory
    public var coordinate: Coordinate
    /// Direction of travel of the reporter, to tell carriageways apart.
    public var heading: Double?
    public var createdAt: Date
    public var expiresAt: Date
    public var confirmations: Int
    public var dismissals: Int
    public var note: String?

    public init(id: String, category: ReportCategory, coordinate: Coordinate, heading: Double?, createdAt: Date,
                expiresAt: Date, confirmations: Int = 0, dismissals: Int = 0, note: String? = nil) {
        self.id = id
        self.category = category
        self.coordinate = coordinate
        self.heading = heading
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.confirmations = confirmations
        self.dismissals = dismissals
        self.note = note
    }

    public func isExpired(at date: Date) -> Bool { date >= expiresAt }
}

public enum ReportConfidence: String, Codable, Sendable { case unconfirmed, low, medium, high }

/// Rules shared by the app and mirrored by the reference backend: lifetime, merging of
/// duplicates and a confidence label. Confidence describes how many drivers agree, never
/// independent verification, and the UI always says "Reported by drivers".
public enum ReportPolicy {
    /// Each confirmation extends the report by half its base lifetime, up to 3× in total.
    public static func expiry(for report: CommunityReport, confirmedAt date: Date) -> Date {
        let base = report.category.baseLifetime
        let extended = max(report.expiresAt, date.addingTimeInterval(base / 2))
        let cap = report.createdAt.addingTimeInterval(base * 3)
        return min(extended, cap)
    }

    /// Two dismissals more than confirmations removes a report.
    public static func shouldRemove(_ report: CommunityReport) -> Bool {
        report.dismissals >= 2 && report.dismissals >= report.confirmations + 2
    }

    public static func confidence(of report: CommunityReport) -> ReportConfidence {
        let score = Double(report.confirmations + 1) / Double(report.confirmations + report.dismissals + 2)
        if report.confirmations == 0 { return .unconfirmed }
        if report.confirmations >= 3 && score >= 0.75 { return .high }
        if score >= 0.6 { return .medium }
        return .low
    }

    /// Finds an existing live report the new one duplicates: same category, within the
    /// merge radius, and (when both have a heading) traveling roughly the same way.
    public static func duplicate(of category: ReportCategory, at coordinate: Coordinate, heading: Double?,
                                 among reports: [CommunityReport], now: Date) -> CommunityReport? {
        reports
            .filter { $0.category == category && !$0.isExpired(at: now) }
            .filter { GeoMath.distance($0.coordinate, coordinate) <= category.mergeRadius }
            .filter { r in
                guard let h1 = r.heading, let h2 = heading else { return true }
                return abs(GeoMath.angleDifference(from: h1, to: h2)) <= 60
            }
            .min { GeoMath.distance($0.coordinate, coordinate) < GeoMath.distance($1.coordinate, coordinate) }
    }
}

/// A sliding-window rate limiter. The app uses it to stop accidental repeat taps before
/// they reach the backend; the backend enforces its own, stricter limits.
public struct RateLimiter: Codable, Sendable {
    public var minimumInterval: TimeInterval
    public var maxPerWindow: Int
    public var window: TimeInterval
    public private(set) var history: [Date] = []

    public init(minimumInterval: TimeInterval = 30, maxPerWindow: Int = 10, window: TimeInterval = 3600) {
        self.minimumInterval = minimumInterval
        self.maxPerWindow = maxPerWindow
        self.window = window
    }

    public enum Decision: Equatable, Sendable { case allowed, wait(TimeInterval) }

    public func check(at now: Date) -> Decision {
        let recent = history.filter { now.timeIntervalSince($0) < window }
        if let last = recent.max(), now.timeIntervalSince(last) < minimumInterval {
            return .wait(minimumInterval - now.timeIntervalSince(last))
        }
        if recent.count >= maxPerWindow, let oldest = recent.min() {
            return .wait(window - now.timeIntervalSince(oldest))
        }
        return .allowed
    }

    public mutating func record(at now: Date) {
        history = history.filter { now.timeIntervalSince($0) < window } + [now]
    }
}
