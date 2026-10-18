import Foundation

public enum GuidanceLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Every announcement: early notice, approach and the maneuver itself.
    case full
    /// Only the maneuver itself, reroutes and arrival.
    case alertsOnly
    /// Nothing is spoken; visual guidance continues.
    case muted
    public var id: String { rawValue }
}

/// An utterance for the voice guidance manager.
public struct Announcement: Sendable, Equatable {
    public enum Stage: String, Sendable { case departure, prepare, approach, imminent, arrival, reroute, notice }
    public var text: String
    public var stage: Stage
    public var stepIndex: Int?
    /// Imminent maneuvers interrupt anything still being spoken.
    public var interrupts: Bool

    public init(text: String, stage: Stage, stepIndex: Int? = nil, interrupts: Bool) {
        self.text = text
        self.stage = stage
        self.stepIndex = stepIndex
        self.interrupts = interrupts
    }
}

/// Sentence templates for spoken guidance. The default is English; the app supplies a
/// localized phrasebook. Instruction text itself always comes from the routing provider,
/// which already localizes it to the device language.
public struct GuidancePhrasebook: Sendable {
    public var inDistance: @Sendable (_ distance: String, _ instruction: String) -> String
    public var then: @Sendable (_ first: String, _ second: String) -> String
    public var rerouted: String
    public var arrivedAtStop: @Sendable (_ name: String) -> String

    public init(inDistance: @escaping @Sendable (String, String) -> String,
                then: @escaping @Sendable (String, String) -> String,
                rerouted: String,
                arrivedAtStop: @escaping @Sendable (String) -> String) {
        self.inDistance = inDistance
        self.then = then
        self.rerouted = rerouted
        self.arrivedAtStop = arrivedAtStop
    }

    public static let english = GuidancePhrasebook(
        inDistance: { d, i in "In \(d), \(GuidancePhrasebook.lowercasingFirst(i))" },
        then: { a, b in "\(a), then \(GuidancePhrasebook.lowercasingFirst(b))" },
        rerouted: "Route updated.",
        arrivedAtStop: { "You have reached \($0)." }
    )

    /// Lower-cases the first letter of an instruction ("Turn right" → "turn right") so it
    /// reads as one sentence after a prefix, unless the word looks like a proper noun or
    /// an abbreviation (two capitals in a row, as in "I-280").
    public static func lowercasingFirst(_ s: String) -> String {
        guard let first = s.first, first.isUppercase else { return s }
        let second = s.dropFirst().first
        if let second, second.isUppercase || second == "-" || second.isNumber { return s }
        return first.lowercased() + s.dropFirst()
    }
}

/// Decides when to speak each maneuver. Distances scale with speed so a highway exit
/// gets an early warning while a city turn is not announced a kilometer ahead.
public struct GuidanceScheduler: Sendable {
    public var level: GuidanceLevel
    public var units: UnitSystem
    public var phrasebook: GuidancePhrasebook
    /// A maneuver closer than this after the upcoming one is chained with "then".
    public var chainDistance: Double = 150

    private var announced: [Int: Set<Announcement.Stage>] = [:]
    private var departed = false

    public init(level: GuidanceLevel, units: UnitSystem, phrasebook: GuidancePhrasebook = .english) {
        self.level = level
        self.units = units
        self.phrasebook = phrasebook
    }

    public struct Thresholds: Equatable, Sendable {
        public var prepare: Double
        public var approach: Double
        public var imminent: Double
    }

    public static func thresholds(forSpeed speed: Double) -> Thresholds {
        let v = max(0, speed)
        if v >= 22 { // about 80 km/h and above
            return Thresholds(prepare: 2000, approach: 800, imminent: min(400, max(150, v * 7)))
        }
        if v >= 11 { // about 40–80 km/h
            return Thresholds(prepare: 1000, approach: 400, imminent: min(150, max(60, v * 6)))
        }
        return Thresholds(prepare: 500, approach: 200, imminent: max(35, v * 6))
    }

    public mutating func reset() {
        announced = [:]
        departed = false
    }

    /// Returns at most one announcement for the given progress.
    public mutating func next(for progress: RouteProgress, route: Route, speed: Double) -> Announcement? {
        guard level != .muted else { return nil }
        guard let upcoming = progress.upcomingStepIndex, let distance = progress.distanceToUpcomingManeuver,
              upcoming < route.steps.count else { return nil }
        let step = route.steps[upcoming]
        let instruction = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never speak a maneuver the provider did not describe.
        guard !instruction.isEmpty else { return nil }

        let t = Self.thresholds(forSpeed: speed)
        var done = announced[upcoming] ?? []
        defer { announced[upcoming] = done }

        if !departed {
            departed = true
            if level == .full, distance > t.imminent {
                done.insert(.departure)
                let d = DistanceFormatter.guidance(meters: distance, system: units).spoken
                // Skip far stages that would repeat almost the same sentence right after.
                if distance <= t.prepare * 1.5 { done.insert(.prepare) }
                if distance <= t.approach * 1.5 { done.insert(.approach) }
                return Announcement(text: phrasebook.inDistance(d, instruction), stage: .departure, stepIndex: upcoming, interrupts: false)
            }
        }

        if distance <= t.imminent {
            guard !done.contains(.imminent) else { return nil }
            done.insert(.imminent)
            done.insert(.approach)
            done.insert(.prepare)
            var text = instruction
            if let following = progress.followingStepIndex, following < route.steps.count,
               let gap = progress.distanceFromUpcomingToFollowing, gap <= chainDistance {
                let next = route.steps[following].instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                if !next.isEmpty { text = phrasebook.then(instruction, next) }
            }
            let stage: Announcement.Stage = step.maneuver == .arrive ? .arrival : .imminent
            return Announcement(text: text, stage: stage, stepIndex: upcoming, interrupts: true)
        }

        guard level == .full else { return nil }

        if distance <= t.approach, !done.contains(.approach) {
            done.insert(.approach)
            done.insert(.prepare)
            // Too close to the imminent call to be worth a separate sentence.
            guard distance > t.imminent * 1.5 else { return nil }
            let d = DistanceFormatter.guidance(meters: distance, system: units).spoken
            return Announcement(text: phrasebook.inDistance(d, instruction), stage: .approach, stepIndex: upcoming, interrupts: false)
        }

        if distance <= t.prepare, !done.contains(.prepare) {
            done.insert(.prepare)
            guard distance > t.approach * 1.5 else { return nil }
            let d = DistanceFormatter.guidance(meters: distance, system: units).spoken
            return Announcement(text: phrasebook.inDistance(d, instruction), stage: .prepare, stepIndex: upcoming, interrupts: false)
        }
        return nil
    }
}
