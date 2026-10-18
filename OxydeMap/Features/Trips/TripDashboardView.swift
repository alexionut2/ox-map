import SwiftUI
import SwiftData
import MapKit
import OxydeCore

/// Optional driving history. Off by default; explains what is stored; everything can be
/// deleted. Shows distance and time, never speed rankings or "achievements".
struct TripDashboardView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TripRecord.startedAt, order: .reverse) private var trips: [TripRecord]
    @Query(sort: \RecentDestination.useCount, order: .reverse) private var frequent: [RecentDestination]
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section {
                    Toggle("Record trips", isOn: $settings.value.tripHistoryEnabled)
                        .accessibilityIdentifier("trips.toggle")
                    Picker("Detail", selection: $settings.value.tripPrecision) {
                        Text("Approximate").tag(TripPrecision.approximate)
                        Text("Precise").tag(TripPrecision.precise)
                    }
                    .disabled(!settings.value.tripHistoryEnabled)
                } footer: {
                    Text(settings.value.tripPrecision == .approximate
                         ? "Stored on this iPhone only: date, distance, duration, average moving speed, destination name, and start and end rounded to about 100 m. No route is kept."
                         : "Stored on this iPhone only: the above, exact start and end, and a simplified outline of the route driven.")
                }
                if !trips.isEmpty {
                    Section("Last 30 days") {
                        let recent = trips.filter { $0.startedAt > Date().addingTimeInterval(-30 * 86400) }
                        let units = settings.value.resolvedUnits
                        LabeledContent("Trips", value: "\(recent.count)")
                        LabeledContent("Distance", value: DistanceFormatter.guidance(meters: recent.reduce(0) { $0 + $1.distance }, system: units).display)
                        LabeledContent("Time driving", value: DurationFormatter.short(recent.reduce(0) { $0 + $1.duration }))
                    }
                    Section("Recent trips") {
                        ForEach(trips) { t in
                            NavigationLink { TripDetailView(trip: t) } label: { TripRow(trip: t) }
                        }
                        .onDelete { idx in idx.forEach { context.delete(trips[$0]) }; try? context.save() }
                    }
                } else if settings.value.tripHistoryEnabled {
                    Section { Text("Trips appear here after you finish navigating.").foregroundStyle(.secondary) }
                }
                if !frequent.isEmpty {
                    Section("Frequent destinations") {
                        ForEach(frequent.prefix(5)) { r in LabeledContent(r.name, value: "\(r.useCount)×") }
                    }
                }
                if !trips.isEmpty {
                    Section {
                        Button("Delete All Trips", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle("Trips")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Delete all recorded trips?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { model.persistence.deleteAllTrips() }
            }
        }
    }
}

struct TripRow: View {
    @Environment(SettingsStore.self) private var settings
    let trip: TripRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.destinationName ?? "Trip").font(.headline)
            Text("\(trip.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(DistanceFormatter.guidance(meters: trip.distance, system: settings.value.resolvedUnits).display) · \(DurationFormatter.short(trip.duration))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TripDetailView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var context
    @Bindable var trip: TripRecord

    var body: some View {
        let units = settings.value.resolvedUnits
        List {
            if !trip.shape.isEmpty || trip.start != nil {
                Map {
                    if trip.shape.count > 1 {
                        MapPolyline(coordinates: trip.shape.map(\.cl)).stroke(.tint, lineWidth: 5)
                    }
                    if let s = trip.start { Marker("Start", coordinate: s.cl) }
                    if let e = trip.end { Marker("End", coordinate: e.cl) }
                }
                .frame(height: 220)
                .listRowInsets(EdgeInsets())
            }
            Section {
                LabeledContent("Distance", value: DistanceFormatter.guidance(meters: trip.distance, system: units).display)
                LabeledContent("Duration", value: DurationFormatter.short(trip.duration))
                LabeledContent("Moving time", value: DurationFormatter.short(trip.movingDuration))
                if let v = trip.averageMovingSpeed {
                    LabeledContent("Average moving speed", value: "\(SpeedFormatter.value(metersPerSecond: v, system: units)) \(SpeedFormatter.unitLabel(units))")
                }
                LabeledContent("Started", value: trip.startedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section("Private note") {
                TextField("Add a note", text: Binding(get: { trip.note ?? "" }, set: { trip.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
            }
        }
        .navigationTitle(trip.destinationName ?? "Trip")
        .onDisappear { try? context.save() }
    }
}
