import SwiftUI
import OxydeCore

/// The driver's garage: level and XP, vehicle icon, Explorer mode and achievements.
struct GarageView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var confirmErase = false
    @State private var confirmReset = false
    @State private var appeared = false
    var onConvoy: (() -> Void)? = nil

    private var progress: DriverProgress { model.play.progress }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    levelCard
                    statsGrid
                    vehicleSection
                    explorerSection
                    if let onConvoy {
                        Button { onConvoy() } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "car.2.fill").font(.title2).foregroundStyle(OX.gradient).frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Convoy").font(.headline)
                                    Text("Drive together and see your friends on the map.").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .oxCard()
                        }
                        .buttonStyle(OxCardButtonStyle())
                    }
                    achievementsSection
                    Toggle("Earn XP and achievements", isOn: $settings.value.progressEnabled)
                        .oxCard()
                    Button("Reset level and achievements", role: .destructive) { confirmReset = true }
                        .font(.footnote)
                        .confirmationDialog("Reset your level, XP and achievements?", isPresented: $confirmReset, titleVisibility: .visible) {
                            Button("Reset", role: .destructive) { model.play.resetProgress() }
                        }
                }
                .padding(.horizontal, OX.gutter)
                .padding(.bottom, 30)
            }
            .background(OX.ink.ignoresSafeArea())
            .navigationTitle("Garage")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.15)) { appeared = true } }
        }
    }

    // MARK: Level

    private var levelCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(OX.line2, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: appeared ? progress.levelProgress : 0)
                    .stroke(OX.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: OX.brand.opacity(0.6), radius: 6)
                VStack(spacing: 0) {
                    Text("\(progress.level)").font(.system(size: 34, weight: .bold)).contentTransition(.numericText())
                    Text("LEVEL").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(OX.muted)
                }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                OxTitle(text: progress.rank, size: 24)
                Text("\(progress.xp) XP").font(.headline).foregroundStyle(OX.lavender).contentTransition(.numericText())
                let next = DriverProgress.threshold(forLevel: progress.level + 1) - progress.xp
                Text("\(next) XP to level \(progress.level + 1)").font(.subheadline).foregroundStyle(OX.muted)
                Text("XP comes from distance, exploring, arriving and helping other drivers. Never from speed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .oxCard(padding: 18)
        .padding(.top, 8)
    }

    private var statsGrid: some View {
        let units = settings.value.resolvedUnits
        let distance = units == .imperial ? progress.metersDriven / 1609.344 : progress.metersDriven / 1000
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            stat(String(format: "%.0f", distance), units == .imperial ? "miles driven" : "km driven", "road.lanes")
            stat("\(progress.arrivals)", "destinations", "flag.checkered")
            stat("\(model.play.grid.count)", "squares explored", "map")
            stat("\(progress.reportsShared)", "reports shared", "exclamationmark.bubble")
        }
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(OX.lavender)
            Text(value).font(.title2.bold()).monospacedDigit().contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(OX.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .oxCard()
    }

    // MARK: Vehicle

    private var vehicleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your vehicle").font(.title3.bold())
            Text("Shown on the map while navigating. CarPlay always uses the simple arrow.")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(VehicleIcon.allCases) { icon in
                        let selected = settings.value.vehicleIcon == icon
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { settings.value.vehicleIcon = icon }
                            model.haptics.tap(enabled: settings.value.hapticsEnabled)
                        } label: {
                            VStack(spacing: 6) {
                                Image(uiImage: VehicleIconRenderer.image(for: icon, tint: UIColor(hex: model.activeTheme.interface.accent)))
                                    .scaleEffect(selected ? 1.15 : 1)
                                Text(icon.title).font(.caption2.weight(.semibold)).lineLimit(1)
                            }
                            .frame(width: 84, height: 92)
                            .background(selected ? OX.surface2 : OX.surface, in: RoundedRectangle(cornerRadius: OX.radiusLarge))
                            .overlay(RoundedRectangle(cornerRadius: OX.radiusLarge)
                                .strokeBorder(selected ? Color.accentColor : OX.line, lineWidth: selected ? 2 : 1))
                        }
                        .buttonStyle(OxCardButtonStyle())
                        .accessibilityLabel(icon.title)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    // MARK: Explorer

    private var explorerSection: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $settings.value.explorerEnabled.animation()) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explorer mode").font(.headline)
                    Text("Like the fog of war in games: squares you drive through light up on the map.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if settings.value.explorerEnabled {
                Text(String(format: "%d squares, about %.0f km² explored.", model.play.grid.count, model.play.grid.areaKm2))
                    .font(.footnote.weight(.medium)).foregroundStyle(OX.lavender)
            }
            Text("Explored squares are saved only on this iPhone and never uploaded. Erase them anytime.")
                .font(.caption).foregroundStyle(.secondary)
            if model.play.grid.count > 0 {
                Button("Erase explored map", role: .destructive) { confirmErase = true }
                    .font(.footnote)
                    .confirmationDialog("Erase all explored squares?", isPresented: $confirmErase, titleVisibility: .visible) {
                        Button("Erase", role: .destructive) { model.play.eraseExploration() }
                    }
            }
        }
        .oxCard()
    }

    // MARK: Achievements

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Achievements").font(.title3.bold())
                Spacer()
                Text("\(progress.unlocked.count)/\(DriverProgress.achievements.count)").font(.subheadline).foregroundStyle(OX.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(DriverProgress.achievements.enumerated()), id: \.element.id) { i, a in
                    let unlocked = progress.isUnlocked(a)
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack {
                            Circle().fill(unlocked ? AnyShapeStyle(OX.gradient) : AnyShapeStyle(OX.surface2)).frame(width: 44, height: 44)
                            Image(systemName: unlocked ? a.symbol : "lock.fill")
                                .foregroundStyle(unlocked ? Color.white : OX.muted)
                        }
                        .shadow(color: unlocked ? OX.brand.opacity(0.5) : .clear, radius: 8)
                        Text(a.title).font(.subheadline.weight(.semibold))
                        Text(a.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("+\(a.xp) XP").font(.caption2.weight(.bold)).foregroundStyle(unlocked ? OX.ok : OX.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                    .oxCard()
                    .opacity(unlocked ? 1 : 0.7)
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(i) * 0.04), value: appeared)
                }
            }
        }
    }
}

/// Level badge for the map's top bar: tapping it opens the garage.
struct LevelBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.play.progress
        ZStack {
            Circle().stroke(OX.line2, lineWidth: 3)
            Circle().trim(from: 0, to: p.levelProgress)
                .stroke(OX.gradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: p.levelProgress)
            Text("\(p.level)").font(.system(size: 17, weight: .bold)).contentTransition(.numericText())
        }
        .frame(width: 38, height: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Garage, level \(p.level)")
    }
}
