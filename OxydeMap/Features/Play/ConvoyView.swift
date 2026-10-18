import SwiftUI
import OxydeCore

/// Convoy: start or join a group drive with a six-character code.
struct ConvoyView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(NavigationSession.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @State private var convoyName = ""
    @State private var code: String
    @FocusState private var codeFocused: Bool

    init(code: String = "") {
        _code = State(initialValue: code)
    }

    private var store: ConvoyStore { model.convoy }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if !store.isConfigured {
                        Banner(symbol: "server.rack",
                               text: "Convoy needs the Oxyde server, which isn't set up in this build (see docs/BACKEND.md).",
                               tone: .warning)
                    }
                    if let snap = store.snapshot {
                        active(snap)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your name in the convoy").font(.subheadline.weight(.semibold))
                            TextField("Driver", text: $settings.value.convoyDisplayName)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(OX.surface2, in: RoundedRectangle(cornerRadius: OX.radiusSmall))
                        }
                        .oxCard()
                        start
                        join
                    }
                    if case .failed(let message) = store.state {
                        Banner(symbol: "exclamationmark.triangle", text: message, tone: .warning)
                    }
                    Text("While you're in a convoy, your position is shared with its members only, about every 5 seconds. The server keeps positions in memory for at most 5 minutes and nothing is saved. Leaving stops sharing immediately.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, OX.gutter)
                .padding(.bottom, 30)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.state)
            }
            .background(OX.ink.ignoresSafeArea())
            .navigationTitle("Convoy")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "car.2.fill").font(.system(size: 30)).foregroundStyle(OX.gradient)
                .symbolEffect(.bounce, value: store.snapshot?.members.count ?? 0)
            Text("Drive together. See where your friends are and head to the same place.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start a convoy").font(.headline)
            TextField("Convoy name (optional)", text: $convoyName)
                .padding(12)
                .background(OX.surface2, in: RoundedRectangle(cornerRadius: OX.radiusSmall))
            Button {
                Task { await store.create(name: convoyName) }
            } label: {
                if store.state == .working { ProgressView() } else { Text("Start Convoy") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!store.isConfigured || store.state == .working)
        }
        .oxCard()
    }

    private var join: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Join with a code").font(.headline)
            TextField("ABC123", text: $code)
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .padding(12)
                .background(OX.surface2, in: RoundedRectangle(cornerRadius: OX.radiusSmall))
            Button("Join Convoy") { Task { await store.join(code: code) } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!store.isConfigured || ConvoyCode.normalize(code) == nil || store.state == .working)
        }
        .oxCard()
    }

    @ViewBuilder
    private func active(_ snap: ConvoySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snap.name).font(.headline)
            HStack {
                Text(snap.code)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(OX.gradient)
                Spacer()
                ShareLink(item: URL(string: "oxydemap://convoy?code=\(snap.code)")!,
                          message: Text("Join my Oxyde Map convoy with code \(snap.code)")) {
                    Image(systemName: "square.and.arrow.up").font(.title3)
                }
            }
            Text("Friends join with this code in Oxyde Map → Garage → Convoy.").font(.caption).foregroundStyle(.secondary)
        }
        .oxCard(padding: 18)

        VStack(alignment: .leading, spacing: 12) {
            Text("Drivers (\(snap.members.count))").font(.headline)
            ForEach(snap.members) { m in
                HStack(spacing: 12) {
                    Circle().fill(Color(hex: HexColor(hex: m.color) ?? "#7C4DFF")).frame(width: 30, height: 30)
                        .overlay(Text(String(m.name.prefix(1)).uppercased()).font(.subheadline.bold()).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.isMe ? "\(m.name) (you)" : m.name).font(.subheadline.weight(.semibold))
                        Text(status(of: m)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !m.isMe, let c = m.coordinate, !m.isStale() {
                        Button {
                            nav.selectedPlace = Place(id: Place.syntheticID(name: m.name, coordinate: c), name: m.name,
                                                      coordinate: c, provider: "Convoy")
                            dismiss()
                        } label: { Image(systemName: "location.fill") }
                        .accessibilityLabel("Show \(m.name) on the map")
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .oxCard()

        VStack(alignment: .leading, spacing: 10) {
            if let dest = snap.destination {
                Label(snap.destinationName ?? "Group destination", systemImage: "flag.checkered").font(.headline)
                Button("Show Group Destination") {
                    let name = snap.destinationName ?? "Group destination"
                    nav.selectedPlace = Place(id: Place.syntheticID(name: name, coordinate: dest), name: name,
                                              coordinate: dest, provider: "Convoy")
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            if let target = nav.stops.last.map({ Place(id: Place.syntheticID(name: $0.name, coordinate: $0.coordinate),
                                                         name: $0.name, coordinate: $0.coordinate, provider: "Convoy") })
                ?? nav.selectedPlace {
                Button("Share “\(target.name)” as Destination") { Task { await store.shareDestination(target) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button("Leave Convoy", role: .destructive) { Task { await store.leave() } }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .oxCard()
    }

    private func status(of m: ConvoyMember) -> String {
        guard let t = m.updatedAt, m.coordinate != nil else { return "Waiting for location" }
        if m.isStale() { return "Last seen \(t.formatted(.relative(presentation: .named)))" }
        return "Live"
    }
}
