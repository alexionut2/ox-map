import SwiftUI
import SwiftData
import OxydeCore

/// Home, work, favorites grouped by collection, and saved routes.
struct SavedPlacesView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationSession.self) private var nav
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPlace.createdAt) private var places: [SavedPlace]
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var routes: [SavedRoute]
    let onPick: (Place) -> Void
    @State private var settingKind: SavedPlaceKind?

    var body: some View {
        NavigationStack {
            List {
                Section("Shortcuts") {
                    shortcut(.home, "house.fill")
                    shortcut(.work, "briefcase.fill")
                }
                let favorites = places.filter { $0.kind == .favorite }
                let groups = Dictionary(grouping: favorites) { $0.collection ?? "Favorites" }
                ForEach(groups.keys.sorted(), id: \.self) { name in
                    Section(name) {
                        ForEach(groups[name] ?? []) { p in
                            Button { onPick(p.place) } label: {
                                VStack(alignment: .leading) {
                                    Text(p.name).foregroundStyle(.primary)
                                    if let a = p.address { Text(a).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { context.delete(p); try? context.save() }
                            }
                            .contextMenu {
                                Menu("Move to Collection") {
                                    ForEach(["Favorites", "Food", "Charging", "Friends", "Trips"], id: \.self) { c in
                                        Button(c) { p.collection = c == "Favorites" ? nil : c; try? context.save() }
                                    }
                                }
                            }
                        }
                    }
                }
                if favorites.isEmpty {
                    Section { Text("Tap the star on any place to save it here.").foregroundStyle(.secondary) }
                }
                Section("Saved routes") {
                    if routes.isEmpty { Text("Save a route from its preview to reuse it.").foregroundStyle(.secondary) }
                    ForEach(routes) { r in
                        Button {
                            r.lastUsed = Date()
                            nav.previewSavedRoute(stops: r.stops, preferences: r.preferences)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(r.name).foregroundStyle(.primary)
                                Text(r.stops.map(\.name).joined(separator: " → ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { idx in idx.forEach { context.delete(routes[$0]) }; try? context.save() }
                }
            }
            .navigationTitle("Saved")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $settingKind) { kind in
                SearchView(results: .constant([]), onPick: { place in
                    model.persistence.save(place, as: kind)
                    settingKind = nil
                })
            }
        }
    }

    private func shortcut(_ kind: SavedPlaceKind, _ symbol: String) -> some View {
        let p = places.first { $0.kind == kind }
        return HStack {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading) {
                Text(kind == .home ? "Home" : "Work")
                Text(p?.address ?? "Not set").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let p { Button("Go") { nav.preview(to: p.place); dismiss() }.buttonStyle(.borderless) }
            Button(p == nil ? "Set" : "Change") { settingKind = kind }.buttonStyle(.borderless)
        }
    }
}

extension SavedPlaceKind: Identifiable { var id: String { rawValue } }
