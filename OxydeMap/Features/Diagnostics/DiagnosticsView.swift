import SwiftUI
import AVFoundation
import OxydeCore

/// What's working, what's missing and why: permissions, services, provider
/// configuration and the implemented/configuration/provider-limited status of every
/// feature.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationManager.self) private var location

    var body: some View {
        let config = model.configuration
        List {
            Section("Permissions") {
                status("Location", location.permission.isAuthorized,
                       location.permission == .notDetermined ? "Not asked yet" : (location.permission.isAuthorized ? "Allowed" : "Off. Navigation needs it."))
                status("Precise location", location.isPreciseAccuracy, location.isPreciseAccuracy ? "On" : "Reduced. Navigation will ask for precise location.")
                status("Background guidance", location.hasBackgroundMode, location.hasBackgroundMode ? "Location background mode is in this build" : "Missing UIBackgroundModes → location")
                if let e = location.lastError { status("Last location error", false, e) }
                if let fix = location.lastFix {
                    LabeledContent("Last fix", value: "±\(Int(fix.horizontalAccuracy)) m, \(fix.timestamp.formatted(.relative(presentation: .named)))")
                }
            }
            Section("Services") {
                status("Network", model.reachability.isOnline, model.reachability.isOnline ? "Online" : "Offline")
                status("Map, search, routing", true, "Apple Maps (no key needed)")
                status("Traffic layer and ETAs", true, "Apple Maps")
                status("Incident and report backend", config.backendBaseURL != nil,
                       config.backendBaseURL?.host ?? "Not configured: set OX_BACKEND_BASE_URL (docs/BACKEND.md)")
                if let e = model.traffic.lastError { status("Last incident fetch", false, e.localizedDescription) }
                if let s = model.traffic.snapshot {
                    LabeledContent("Incidents", value: "\(s.incidents.count) from \(s.sources.joined(separator: ", ")), \(s.fetchedAt.formatted(.relative(presentation: .named)))")
                }
                status("Vector engine", config.vectorEngineAvailable,
                       !AppConfiguration.vectorEngineLinked ? "MapLibre package not added" : (config.vectorTiles == nil ? "No tile source configured" : "Ready"))
                status("Voices", !AVSpeechSynthesisVoice.speechVoices().isEmpty, "\(AVSpeechSynthesisVoice.speechVoices().count) installed")
                status("In-app purchases", model.premium.isConfigured && !model.premium.products.isEmpty,
                       model.premium.isConfigured ? (model.premium.loadError ?? "\(model.premium.products.count) products") : "No product IDs configured")
                status("iCloud sync", model.cloudSync.isAvailable, model.cloudSync.isAvailable ? "Available" : "Not signed in or no entitlement")
                status("CarPlay", model.carPlayConnected, model.carPlayConnected ? "Connected" : "Not connected")
            }
            Section("Routing provider") {
                let c = model.navigation.capabilities
                capability("Alternatives", c.supportsAlternatives)
                capability("Avoid tolls / highways", c.supportsAvoidTolls && c.supportsAvoidHighways)
                capability("Avoid ferries", c.supportsAvoidFerries)
                capability("Traffic-aware travel times", c.trafficAwareTravelTimes)
                capability("Lane guidance", c.providesLaneGuidance)
                capability("Speed limits", c.providesSpeedLimits)
            }
            ForEach(groupedFeatures, id: \.0) { area, items in
                Section(area) {
                    ForEach(items) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(f.name)
                                Spacer()
                                Text(label(f.state)).font(.caption.bold()).foregroundStyle(color(f.state))
                            }
                            if !f.note.isEmpty { Text(f.note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            #if DEBUG
            Section("Developer") {
                Toggle("Unlock premium (debug builds only)", isOn: Binding(get: { model.premium.developerUnlock },
                                                                          set: { model.premium.developerUnlock = $0 }))
            }
            #endif
        }
        .navigationTitle("Diagnostics")
    }

    private var groupedFeatures: [(String, [FeatureStatus])] {
        let all = FeatureCatalog.features(.init(backendConfigured: model.configuration.backendBaseURL != nil,
                                                vectorEngineAvailable: model.configuration.vectorEngineAvailable,
                                                storeConfigured: model.premium.isConfigured))
        var order: [String] = []
        var groups: [String: [FeatureStatus]] = [:]
        for f in all {
            if groups[f.area] == nil { order.append(f.area) }
            groups[f.area, default: []].append(f)
        }
        return order.map { ($0, groups[$0]!) }
    }

    private func status(_ title: String, _ ok: Bool, _ detail: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func capability(_ title: String, _ ok: Bool) -> some View {
        LabeledContent(title, value: ok ? "Yes" : "Not provided")
    }

    private func label(_ s: FeatureState) -> String {
        switch s {
        case .implemented: return "Working"
        case .requiresConfiguration: return "Needs setup"
        case .providerLimited: return "Provider limit"
        case .planned: return "Planned"
        }
    }

    private func color(_ s: FeatureState) -> Color {
        switch s {
        case .implemented: return .green
        case .requiresConfiguration: return .orange
        case .providerLimited: return .secondary
        case .planned: return .blue
        }
    }
}
