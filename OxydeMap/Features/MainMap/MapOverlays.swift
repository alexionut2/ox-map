import SwiftUI
import SwiftData
import OxydeCore

/// Speed from GPS. The speed limit is shown only when a provider supplies it; Apple
/// Maps does not, so no limit is displayed rather than a guessed one.
struct SpeedometerView: View {
    let fix: LocationFix?
    let style: SpeedometerStyle
    let units: UnitSystem
    let typography: TypographyStyle
    var speedLimit: Double? = nil

    private var value: String {
        guard let f = fix, f.hasValidSpeed else { return "—" }
        return "\(SpeedFormatter.value(metersPerSecond: f.speed, system: units))"
    }

    var body: some View {
        Group {
            switch style {
            case .hidden: EmptyView()
            case .minimal:
                Text("\(value) \(SpeedFormatter.unitLabel(units))").font(typography.font(15)).monospacedDigit()
                    .padding(.horizontal, 12).padding(.vertical, 8).oxPanel(.glass, cornerRadius: 14)
            case .digital:
                VStack(spacing: 0) {
                    Text(value).font(typography.font(30, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.3), value: value)
                    Text(SpeedFormatter.unitLabel(units)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                .frame(width: 76, height: 76)
                .oxPanel(.solid, cornerRadius: 38)
            case .ring:
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.12), lineWidth: 6)
                    Circle().trim(from: 0, to: ringFraction).stroke(.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .shadow(color: Color.accentColor.opacity(0.5), radius: 4)
                        .animation(.easeOut(duration: 0.5), value: ringFraction)
                    VStack(spacing: 0) {
                        Text(value).font(typography.font(26, weight: .bold)).monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.3), value: value)
                        Text(SpeedFormatter.unitLabel(units)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 84, height: 84)
                .padding(4)
                .oxPanel(.solid, cornerRadius: 46)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let speedLimit {
                Text("\(SpeedFormatter.value(metersPerSecond: speedLimit, system: units))")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white).overlay(Circle().stroke(.red, lineWidth: 4)))
                    .offset(x: 10, y: -10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed \(value) \(SpeedFormatter.unitLabel(units))")
    }

    /// The ring fills over 0–200 km/h (or 0–125 mph) as a visual scale only.
    private var ringFraction: CGFloat {
        guard let f = fix, f.hasValidSpeed else { return 0 }
        let maxSpeed = units == .imperial ? 55.9 : 55.6
        return CGFloat(min(1, f.speed / maxSpeed)) * 0.75
    }
}

/// Offline, permission and service-state banners for the exploring map.
struct StatusBanners: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationManager.self) private var location

    var body: some View {
        VStack(spacing: 8) {
            if !model.reachability.isOnline {
                Banner(symbol: "wifi.slash", text: "Offline. Search, routing and traffic need a connection; the map shows cached areas.",
                       tone: .warning)
            }
            if location.permission == .denied || location.permission == .restricted {
                Banner(symbol: "location.slash", text: "Location is off. Turn it on in Settings to navigate.", tone: .warning,
                       action: ("Settings", { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }))
            } else if location.permission.isAuthorized && !location.isPreciseAccuracy {
                Banner(symbol: "location.circle", text: "Precise location is off. Navigation will ask for it when you start.", tone: .info)
            }
        }
    }
}

struct Banner: View {
    enum Tone { case info, warning, critical }
    let symbol: String
    let text: String
    var tone: Tone = .info
    var action: (String, () -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.footnote.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action { Button(action.0, action: action.1).font(.footnote.bold()) }
        }
        .padding(12)
        .oxPanel(.glass, cornerRadius: 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var color: Color {
        switch tone {
        case .info: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

/// Home, work, favorites and recents in one row.
struct QuickAccessBar: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationSession.self) private var nav
    @Query(sort: \SavedPlace.createdAt) private var saved: [SavedPlace]
    @Query(sort: \RecentDestination.lastUsed, order: .reverse) private var recents: [RecentDestination]
    let onSaved: () -> Void
    let onTrips: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip("Home", "house.fill", saved.first { $0.kind == .home }?.place)
                chip("Work", "briefcase.fill", saved.first { $0.kind == .work }?.place)
                Button(action: onSaved) { label("Saved", "star.fill") }.buttonStyle(.plain)
                ForEach(recents.prefix(4)) { r in
                    Button { nav.preview(to: r.place) } label: { label(r.name, "clock.arrow.circlepath") }.buttonStyle(.plain)
                }
                Button(action: onTrips) { label("Trips", "chart.xyaxis.line") }.buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func chip(_ title: String, _ symbol: String, _ place: Place?) -> some View {
        Button {
            if let place { nav.preview(to: place) } else { onSaved() }
        } label: {
            label(place == nil ? "Set \(title)" : title, symbol)
        }
        .buttonStyle(.plain)
    }

    private func label(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .oxPanel(model.activeTheme.interface.panel, cornerRadius: 22)
    }
}

/// A selected place: details that MapKit actually provides, and actions.
struct PlaceCard: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationSession.self) private var nav
    @Environment(LocationManager.self) private var location
    @Environment(SettingsStore.self) private var settings
    let place: Place
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name).font(.title3.bold()).lineLimit(2)
                    if let a = place.address { Text(a).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    HStack(spacing: 8) {
                        if let cat = place.category { Label(cat.title, systemImage: cat.symbol) }
                        if let d = distanceText { Text(d) }
                        if let r = place.rating { Label(String(format: "%.1f", r), systemImage: "star.fill") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { nav.selectedPlace = nil } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).accessibilityLabel("Close")
            }
            if let hours = place.openingHours, !hours.isEmpty {
                Text(hours.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { nav.preview(to: place) } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("place.directions")
                Menu {
                    Button("Add to Favorites", systemImage: "star") { save(.favorite) }
                    Button("Set as Home", systemImage: "house") { save(.home) }
                    Button("Set as Work", systemImage: "briefcase") { save(.work) }
                } label: {
                    Image(systemName: saved ? "star.fill" : "star").font(.title3).frame(width: 54, height: 54)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
                if let phone = place.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Link(destination: url) {
                        Image(systemName: "phone.fill").font(.title3).frame(width: 54, height: 54)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityLabel("Call")
                }
                ShareLink(item: PlaceShareLink.url(for: place), subject: Text(place.name), message: Text(place.address ?? "")) {
                    Image(systemName: "square.and.arrow.up").font(.title3).frame(width: 54, height: 54)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            if let site = place.website {
                Link(site.host ?? site.absoluteString, destination: site).font(.footnote)
            }
            if place.category == .evCharging && place.charger == nil {
                Text("Connector types and charging speed aren't provided by Apple Maps.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .oxPanel(model.activeTheme.interface.panel)
        .onAppear { saved = model.persistence.isFavorite(place) }
    }

    private var distanceText: String? {
        guard let here = location.lastFix?.coordinate else { return nil }
        return DistanceFormatter.guidance(meters: GeoMath.distance(here, place.coordinate), system: settings.value.resolvedUnits).display
    }

    private func save(_ kind: SavedPlaceKind) {
        model.persistence.save(place, as: kind)
        saved = true
        model.haptics.success(enabled: settings.value.hapticsEnabled)
    }
}

enum PlaceShareLink {
    /// An Apple Maps link anyone can open, carrying the place name and coordinates.
    static func url(for place: Place) -> URL {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "ll", value: "\(place.coordinate.latitude),\(place.coordinate.longitude)"),
                        URLQueryItem(name: "q", value: place.name)]
        return c.url!
    }

    /// An Apple Maps directions link through every stop.
    static func url(for stops: [Waypoint]) -> URL? {
        guard let last = stops.last else { return nil }
        var c = URLComponents(string: "https://maps.apple.com/")!
        let chain = stops.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" }.joined(separator: "+to:")
        c.queryItems = [URLQueryItem(name: "daddr", value: chain), URLQueryItem(name: "dirflg", value: "d"),
                        URLQueryItem(name: "q", value: last.name)]
        return c.url
    }
}

struct RecoveryCard: View {
    @Environment(NavigationSession.self) private var nav
    @Environment(AppModel.self) private var model
    let recovery: RecoverySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resume navigation?").font(.headline)
            Text("Guidance to \(recovery.stops.last?.name ?? "your destination") stopped when the app closed.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("Resume") { nav.resumeRecovered() }.buttonStyle(PrimaryButtonStyle())
                Button("Dismiss") { nav.discardRecovery() }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .oxPanel(model.activeTheme.interface.panel)
    }
}

struct ArrivalCard: View {
    @Environment(NavigationSession.self) private var nav
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.checkered").font(.largeTitle).foregroundStyle(.tint)
            Text("You've arrived").font(.title2.bold())
            if let name = nav.stops.last?.name { Text(name).foregroundStyle(.secondary) }
            Button("Done") { nav.dismissArrival() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .oxPanel(model.activeTheme.interface.panel)
    }
}

/// Quick map options without opening Map Studio.
struct LayersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Style") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.themes.allThemes) { t in
                                let locked = t.isPremium && !model.premium.isUnlocked
                                Button {
                                    guard !locked else { return }
                                    model.useTheme(t)
                                    settings.value.cameraMode = t.camera.mode
                                } label: {
                                    VStack(spacing: 6) {
                                        Circle().fill(Color(hex: t.palette.background))
                                            .overlay(Circle().stroke(Color(hex: t.route.color), lineWidth: 4))
                                            .overlay { if locked { Image(systemName: "lock.fill").font(.caption) } }
                                            .frame(width: 48, height: 48)
                                        Text(t.name.replacingOccurrences(of: "Oxyde ", with: "")).font(.caption2).lineLimit(1)
                                    }
                                    .frame(width: 70)
                                    .opacity(model.activeTheme.id == t.id ? 1 : 0.75)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section("On the map") {
                    Toggle("Live traffic", isOn: $settings.value.showsTraffic)
                    Toggle("Points of interest", isOn: $settings.value.showsPOI)
                    Toggle("Driver reports", isOn: $settings.value.communityReportsEnabled)
                    Picker("Camera", selection: $settings.value.cameraMode) {
                        ForEach(CameraMode.allCases) { Text($0.title).tag($0) }
                    }
                }
                if !model.traffic.isConfigured {
                    Section {
                        Text("Accidents, closures and roadworks need the Oxyde traffic service, which isn't set up in this build. Live traffic colors on roads come from Apple Maps and work without it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct IncidentDetailView: View {
    @Environment(AppModel.self) private var model
    let incident: Incident
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: MapKitMapController.symbol(for: incident.kind)).font(.title).foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(incident.title).font(.title3.bold())
                    Text(incident.source.attribution).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let d = incident.detail { Text(d) }
            if let delay = incident.delaySeconds, delay > 0 {
                Label("Delay about \(DurationFormatter.short(delay))", systemImage: "clock")
            }
            Text("Updated \(incident.updatedAt.formatted(.relative(presentation: .named)))").font(.footnote).foregroundStyle(.secondary)
            if let report = incident.report {
                let confidence = ReportPolicy.confidence(of: report)
                Text("Reported by drivers · \(confirmationText(report, confidence))").font(.footnote).foregroundStyle(.secondary)
                if model.reports.hasVoted(on: report.id) {
                    Text("Thanks for your feedback.").font(.footnote)
                } else {
                    HStack {
                        Button("Still there") { vote(.confirm, report) }.buttonStyle(PrimaryButtonStyle())
                        Button("Not there") { vote(.dismiss, report) }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.red) }
            Spacer()
        }
        .padding(20)
    }

    private func confirmationText(_ r: CommunityReport, _ c: ReportConfidence) -> String {
        switch c {
        case .unconfirmed: return "not yet confirmed"
        default: return "\(r.confirmations) confirmed, \(r.dismissals) said it's gone"
        }
    }

    private func vote(_ v: ReportVote, _ r: CommunityReport) {
        Task { message = await model.reports.vote(v, on: r, traffic: model.traffic) }
    }
}
