import SwiftUI
import SwiftData
import MapKit
import OxydeCore

/// Destination search: autocomplete, categories, along-route search, recents and saved
/// places. Everything listed comes from MapKit or the user's own data.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationSession.self) private var nav
    @Environment(LocationManager.self) private var location
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RecentDestination.lastUsed, order: .reverse) private var recents: [RecentDestination]
    @Query(sort: \SavedPlace.createdAt) private var saved: [SavedPlace]

    @Binding var results: [Place]
    let onPick: (Place) -> Void

    @State private var query = ""
    @State private var completer = SearchCompleter()
    @State private var categoryResults: [Place] = []
    @State private var alongRoute: [AlongRouteRanker.Candidate] = []
    @State private var activeCategory: PlaceCategory?
    @State private var isSearching = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var region: SearchRegion? {
        location.lastFix.map { SearchRegion(center: $0.coordinate, radius: 20_000) }
    }

    private var navigating: Bool { nav.phase == .navigating }

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty {
                    suggestionsSection
                } else if let cat = activeCategory {
                    categorySection(cat)
                } else {
                    categoriesSection
                    if !saved.isEmpty { savedSection }
                    if !recents.isEmpty { recentsSection }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search places, addresses or coordinates")
            .searchFocusedIfAvailable($focused)
            .onSubmit(of: .search) { Task { await runTextSearch() } }
            .onChange(of: query) { _, q in
                error = nil
                completer.update(query: q, region: region)
            }
            .navigationTitle(navigating ? "Search" : "Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { focused = true }
            .overlay { if isSearching { ProgressView().controlSize(.large) } }
        }
    }

    // MARK: Sections

    private var suggestionsSection: some View {
        Section {
            if let c = CoordinateParser.parse(query) {
                Button {
                    onPick(Place(id: Place.syntheticID(name: query, coordinate: c),
                                 name: String(format: "%.5f, %.5f", c.latitude, c.longitude), coordinate: c, provider: "Coordinates"))
                } label: { Label("Go to \(String(format: "%.5f, %.5f", c.latitude, c.longitude))", systemImage: "scope") }
            }
            ForEach(completer.results, id: \.self) { s in
                Button { Task { await pick(s) } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).foregroundStyle(.primary)
                        if !s.subtitle.isEmpty { Text(s.subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if completer.results.isEmpty, CoordinateParser.parse(query) == nil {
                Button { Task { await runTextSearch() } } label: { Label("Search for “\(query)”", systemImage: "magnifyingglass") }
            }
            if let e = completer.error { Text(e).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var categoriesSection: some View {
        Section(navigating ? "Along your route" : "Nearby") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(navigating ? PlaceCategory.alongRoute : PlaceCategory.quickSearch) { cat in
                    Button { Task { await runCategory(cat) } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: cat.symbol).font(.title2).frame(height: 30)
                            Text(cat.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("category.\(cat.rawValue)")
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func categorySection(_ cat: PlaceCategory) -> some View {
        Section {
            Button { activeCategory = nil; results = [] } label: { Label("All categories", systemImage: "chevron.left") }
            if cat == .evCharging {
                Text("Apple Maps finds chargers but doesn't provide connector types or charging speed, so those filters aren't available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if navigating {
                if alongRoute.isEmpty && !isSearching { Text("Nothing found along the rest of the route.").foregroundStyle(.secondary) }
                ForEach(alongRoute, id: \.place.id) { c in
                    placeRow(c.place, detail: "\(DistanceFormatter.guidance(meters: c.distanceAhead, system: settings.value.resolvedUnits).display) ahead · \(DistanceFormatter.guidance(meters: c.detourOffset, system: settings.value.resolvedUnits).display) off route") {
                        nav.addStop(c.place)
                        dismiss()
                    }
                }
            } else {
                if categoryResults.isEmpty && !isSearching { Text("No \(cat.title.lowercased()) found nearby.").foregroundStyle(.secondary) }
                ForEach(categoryResults) { p in placeRow(p) { onPick(p) } }
            }
        } header: {
            Text(cat.title)
        }
    }

    private var savedSection: some View {
        Section("Saved") {
            ForEach(saved) { s in
                placeRow(s.place, symbol: s.kind == .home ? "house.fill" : s.kind == .work ? "briefcase.fill" : "star.fill") { onPick(s.place) }
            }
        }
    }

    private var recentsSection: some View {
        Section("Recent") {
            ForEach(recents.prefix(10)) { r in
                placeRow(r.place, symbol: "clock.arrow.circlepath") { onPick(r.place) }
            }
            .onDelete { idx in
                for i in idx { model.persistence.context.delete(recents[i]) }
                try? model.persistence.context.save()
            }
        }
    }

    private func placeRow(_ p: Place, symbol: String? = nil, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol ?? p.category?.symbol ?? "mappin.circle.fill").foregroundStyle(.tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).foregroundStyle(.primary)
                    if let d = detail ?? p.address { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                if let here = location.lastFix?.coordinate, detail == nil {
                    Text(DistanceFormatter.guidance(meters: GeoMath.distance(here, p.coordinate), system: settings.value.resolvedUnits).display)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Actions

    private func pick(_ completion: MKLocalSearchCompletion) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await model.search.search(completion: completion, near: region)
            if found.count == 1, let p = found.first {
                results = [p]
                onPick(p)
            } else if let first = found.first {
                results = found
                onPick(first)
            } else {
                error = "No results."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runTextSearch() async {
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await model.search.search(text: query, near: region)
            results = found
            if let first = found.first { onPick(first) } else { error = "No results for “\(query)”." }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runCategory(_ cat: PlaceCategory) async {
        activeCategory = cat
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            if navigating, let route = nav.activeRoute, let p = nav.progress {
                alongRoute = try await model.search.searchAlongRoute(category: cat, route: route, traveled: p.distanceTraveled)
            } else if let region {
                categoryResults = try await model.search.search(category: cat, near: SearchRegion(center: region.center, radius: 5000))
                results = categoryResults
            } else {
                error = "Turn on location to search nearby."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension View {
    /// `searchFocused` needs iOS 18; on iOS 17 the search field simply isn't auto-focused.
    @ViewBuilder
    func searchFocusedIfAvailable(_ binding: FocusState<Bool>.Binding) -> some View {
        if #available(iOS 18.0, *) {
            searchFocused(binding)
        } else {
            self
        }
    }
}
