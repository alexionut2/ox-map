import AppIntents
import OxydeCore

/// Report categories offered to Siri and Shortcuts. Police and speed-camera reports are
/// left out here because they are restricted in several countries; the in-app sheet
/// applies the full region policy.
enum ReportKindEntity: String, AppEnum {
    case accident, trafficJam, hazard, roadworks, closure, objectOnRoad, stoppedVehicle

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Report"
    static var caseDisplayRepresentations: [ReportKindEntity: DisplayRepresentation] = [
        .accident: "Accident", .trafficJam: "Traffic", .hazard: "Hazard", .roadworks: "Roadworks",
        .closure: "Road closure", .objectOnRoad: "Object on road", .stoppedVehicle: "Stopped vehicle",
    ]

    var category: ReportCategory { ReportCategory(rawValue: rawValue) ?? .other }
}

/// "Report traffic in Oxyde Map": hands-free reporting at the current position.
struct ReportIncidentIntent: AppIntent {
    static var title: LocalizedStringResource = "Report on the Road"
    static var description = IntentDescription("Shares a report at your current location with other Oxyde Map drivers.")
    static var openAppWhenRun = false

    @Parameter(title: "Report", default: .trafficJam)
    var kind: ReportKindEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let reports = model.reports
        guard reports.isConfigured else {
            return .result(dialog: "Community reporting isn't set up in this build of Oxyde Map.")
        }
        guard reports.allowedCategories.contains(kind.category) else {
            return .result(dialog: "That kind of report isn't available in your region.")
        }
        reports.submit(kind.category, at: model.location.lastFix, traffic: model.traffic)
        // The store keeps its normal undo window, then sends. Wait for the real outcome.
        for _ in 0..<60 {
            switch reports.state {
            case .sent: return .result(dialog: "Thanks. Your \(kind.category.title.lowercased()) report was shared.")
            case .failed(let message): return .result(dialog: "\(message)")
            case .idle: return .result(dialog: "The report was cancelled.")
            default: try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return .result(dialog: "The report is still sending.")
    }
}

struct OxydeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ReportIncidentIntent(),
                    phrases: ["Report traffic in \(.applicationName)", "Report \(\.$kind) in \(.applicationName)"],
                    shortTitle: "Report", systemImageName: "exclamationmark.bubble.fill")
    }
}
