import SwiftUI
import SwiftData
import OxydeCore

/// Route options with provider travel times, stops, preferences and Start.
struct RoutePreviewPanel: View {
    @Environment(NavigationSession.self) private var nav
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var context
    let onAddStop: () -> Void
    @State private var showStops = false
    @State private var showPrefs = false
    @State private var savedRoute = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if nav.phase == .planning {
                HStack { ProgressView(); Text("Calculating routes…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if let error = nav.planningError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("Try Again") { nav.calculate() }.buttonStyle(SecondaryButtonStyle())
                }
            } else {
                routeList
                Button { nav.start() } label: { Label("Start", systemImage: "location.north.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("route.start")
            }
        }
        .padding(16)
        .oxPanel(model.activeTheme.interface.panel)
        .sheet(isPresented: $showStops) { StopsEditor(onAddStop: { showStops = false; onAddStop() }).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showPrefs) { RoutePreferencesSheet().presentationDetents([.medium]) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(nav.stops.last?.name ?? "Route").font(.headline).lineLimit(1)
                if nav.stops.count > 1 {
                    Text("\(nav.stops.count - 1) stop\(nav.stops.count > 2 ? "s" : "") on the way").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("Stops", systemImage: "list.number") { showStops = true }
                Button("Add Stop", systemImage: "plus") { onAddStop() }
                Button("Route Options", systemImage: "slider.horizontal.3") { showPrefs = true }
                if let url = PlaceShareLink.url(for: nav.stops) {
                    ShareLink(item: url) { Label("Share Route", systemImage: "square.and.arrow.up") }
                }
                Button(savedRoute ? "Saved" : "Save Route", systemImage: "bookmark") { saveRoute() }.disabled(savedRoute)
            } label: {
                Image(systemName: "ellipsis.circle").font(.title2).frame(width: 40, height: 40)
            }
            Button { nav.cancelPlanning() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                .buttonStyle(.plain).accessibilityLabel("Cancel")
        }
    }

    private var routeList: some View {
        let comps = Dictionary(uniqueKeysWithValues: nav.comparisons.map { ($0.routeID, $0) })
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(nav.routes) { r in
                    let selected = r.id == nav.selectedRouteID
                    let c = comps[r.id]
                    Button { nav.selectRoute(r.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(DurationFormatter.short(r.expectedTravelTime)).font(.title2.bold()).monospacedDigit()
                            Text("Arrive \(Date().addingTimeInterval(r.expectedTravelTime).shortTime)").font(.caption).foregroundStyle(.secondary)
                            Text(DistanceFormatter.guidance(meters: r.distance, system: settings.value.resolvedUnits).display + (r.name.isEmpty ? "" : " · \(r.name)"))
                                .font(.caption).lineLimit(1)
                            HStack(spacing: 6) {
                                if c?.isFastest == true { tag("Fastest", .green) }
                                else if let c { tag(DurationFormatter.delta(c.timeDelta), .secondary) }
                                if r.hasTolls { tag("Tolls", .orange) }
                                if r.hasHighways { tag("Highways", .secondary) }
                            }
                            ForEach(r.advisoryNotices.prefix(1), id: \.self) { n in
                                Text(n).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                            }
                        }
                        .padding(12)
                        .frame(width: 200, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(selected ? 0.12 : 0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("Travel times include traffic, from \(nav.capabilities.providerName)").font(.caption2).foregroundStyle(.secondary)
                .offset(y: 16)
        }
        .padding(.bottom, 12)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
    }

    private func saveRoute() {
        context.insert(SavedRoute(name: nav.stops.last?.name ?? "Route", stops: nav.stops, preferences: nav.preferences))
        try? context.save()
        savedRoute = true
    }
}

struct StopsEditor: View {
    @Environment(NavigationSession.self) private var nav
    @Environment(\.dismiss) private var dismiss
    let onAddStop: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Current Location", systemImage: "location.fill").foregroundStyle(.secondary)
                    ForEach(nav.stops) { s in
                        VStack(alignment: .leading) {
                            Text(s.name)
                            if let a = s.address { Text(a).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .onDelete { nav.removeStop(at: $0) }
                    .onMove { nav.moveStops(from: $0, to: $1) }
                }
                Button { onAddStop() } label: { Label("Add Stop", systemImage: "plus.circle.fill") }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Stops")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RoutePreferencesSheet: View {
    @Environment(NavigationSession.self) private var nav
    @State private var prefs = RoutePreferences()

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Avoid tolls", isOn: $prefs.avoidTolls).disabled(!nav.capabilities.supportsAvoidTolls)
                Toggle("Avoid highways", isOn: $prefs.avoidHighways).disabled(!nav.capabilities.supportsAvoidHighways)
                Toggle("Avoid ferries", isOn: $prefs.avoidFerries).disabled(!nav.capabilities.supportsAvoidFerries)
                if !nav.capabilities.supportsAvoidFerries {
                    Text("\(nav.capabilities.providerName) routing doesn't offer a ferry preference.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Route Options")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { prefs = nav.preferences }
            .onChange(of: prefs) { _, p in nav.updatePreferences(p) }
        }
    }
}
