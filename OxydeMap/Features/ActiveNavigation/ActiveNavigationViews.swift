import SwiftUI
import OxydeCore

/// The next maneuver: icon, distance, the provider's instruction, lanes when supplied,
/// and the maneuver after it when it comes soon.
struct ManeuverPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationSession.self) private var nav
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let theme = model.activeTheme
        let cockpit = theme.interface.maneuverPanel == .cockpit
        if let step = nav.upcomingStep, let distance = nav.progress?.distanceToUpcomingManeuver {
            let d = DistanceFormatter.guidance(meters: distance, system: settings.value.resolvedUnits)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: step.maneuver.symbolName)
                        .font(.system(size: cockpit ? 52 : 40, weight: .bold))
                        .foregroundStyle(.tint)
                        .frame(width: cockpit ? 70 : 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.display)
                            .font(theme.interface.typography.font(cockpit ? 40 : 32, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(step.instruction)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                if let lanes = step.lanes, !lanes.isEmpty {
                    LaneGuidanceView(lanes: lanes)
                }
                if let next = nav.followingStep, let gap = nav.progress?.distanceFromUpcomingToFollowing, gap < 400 {
                    HStack(spacing: 8) {
                        Text("Then").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Image(systemName: next.maneuver.symbolName)
                        Text(next.instruction).font(.subheadline).lineLimit(1)
                    }
                }
            }
            .padding(16)
            .oxPanel(theme.interface.panel)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("nav.maneuver")
        } else if nav.progress == nil {
            HStack {
                ProgressView()
                Text(nav.signal == .good ? "Waiting for your position…" : "Searching for GPS…").font(.headline)
                Spacer()
            }
            .padding(16)
            .oxPanel(theme.interface.panel)
        }
    }
}

struct LaneGuidanceView: View {
    let lanes: [LaneInfo]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                Image(systemName: symbol(lane.directions.first ?? .straight))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(lane.isRecommended ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(lane.isRecommended ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .accessibilityLabel("Lane guidance")
    }

    private func symbol(_ d: LaneInfo.Direction) -> String {
        switch d {
        case .straight: return "arrow.up"
        case .slightLeft: return "arrow.up.left"
        case .left, .sharpLeft: return "arrow.turn.up.left"
        case .slightRight: return "arrow.up.right"
        case .right, .sharpRight: return "arrow.turn.up.right"
        case .uTurn: return "arrow.uturn.down"
        }
    }
}

/// Rerouting, GPS state and incidents on the route.
struct NavigationBanners: View {
    @Environment(NavigationSession.self) private var nav
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var checking = false
    @State private var noAlternative = false

    var body: some View {
        VStack(spacing: 8) {
            if nav.isRerouting {
                Banner(symbol: "arrow.triangle.2.circlepath", text: "Finding a new route…")
            } else if let e = nav.rerouteError {
                Banner(symbol: "exclamationmark.triangle", text: "Couldn't update the route (\(e)). Still guiding on the previous route; retrying.",
                       tone: .warning)
            }
            switch nav.signal {
            case .good: EmptyView()
            case .weak: Banner(symbol: "location.slash", text: "Weak GPS signal. Directions may lag.", tone: .warning)
            case .lost: Banner(symbol: "location.slash.fill", text: "GPS signal lost. Guidance resumes when it's back.", tone: .critical)
            }
            if let m = nav.incidentAhead {
                let d = DistanceFormatter.guidance(meters: m.distanceAhead, system: settings.value.resolvedUnits).display
                Banner(symbol: MapKitMapController.symbol(for: m.incident.kind),
                       text: "\(m.incident.title) in \(d) · \(m.incident.source.attribution)",
                       tone: m.incident.roadClosed ? .critical : .warning,
                       action: (checking ? "Checking…" : (noAlternative ? "No other route" : "Avoid"), { avoid() }))
            }
            if !model.reachability.isOnline {
                Banner(symbol: "wifi.slash", text: "Offline. Guidance continues on the current route; rerouting needs a connection.", tone: .warning)
            }
        }
    }

    private func avoid() {
        guard !checking else { return }
        checking = true
        Task {
            if let r = await nav.findRouteAvoidingIncident() { nav.switchTo(r) } else { noAlternative = true }
            checking = false
        }
    }
}

/// ETA, remaining time and distance, plus end, overview and recenter.
struct ActiveNavigationBar: View {
    @Environment(NavigationSession.self) private var nav
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    let onOverview: () -> Void
    let onRecenter: () -> Void
    @State private var confirmEnd = false

    var body: some View {
        let theme = model.activeTheme
        let p = nav.progress
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if let p {
                    switch settings.value.arrivalDisplay {
                    case .arrivalTime:
                        Text(p.estimatedArrival.shortTime).font(theme.interface.typography.font(26, weight: .bold))
                    case .timeRemaining:
                        Text(DurationFormatter.short(p.timeRemaining)).font(theme.interface.typography.font(26, weight: .bold))
                    case .both:
                        Text(p.estimatedArrival.shortTime).font(theme.interface.typography.font(26, weight: .bold))
                        Text(DurationFormatter.short(p.timeRemaining)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(DistanceFormatter.guidance(meters: p.distanceRemaining, system: settings.value.resolvedUnits).display + trafficNote(p))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("—").font(.title.bold())
                }
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("nav.eta")
            Spacer()
            Button(action: onOverview) { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.title3).frame(width: 48, height: 48) }
                .buttonStyle(.plain).accessibilityLabel("Route overview")
            Button(action: onRecenter) { Image(systemName: "location.north.line.fill").font(.title3).frame(width: 48, height: 48) }
                .buttonStyle(.plain).accessibilityLabel("Recenter")
            Button { confirmEnd = true } label: {
                Text("End").font(.headline).foregroundStyle(.white).frame(width: 72, height: 48)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nav.end")
        }
        .padding(14)
        .oxPanel(theme.interface.panel)
        .confirmationDialog("End navigation?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Route", role: .destructive) { nav.stop() }
        }
    }

    /// Says when the travel time behind the ETA was last refreshed, once it's old enough to matter.
    private func trafficNote(_ p: RouteProgress) -> String {
        let age = Date().timeIntervalSince(p.travelTimeUpdatedAt)
        return age > 300 ? " · ETA from \(Int(age / 60)) min ago" : ""
    }
}
