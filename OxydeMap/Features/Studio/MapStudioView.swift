import SwiftUI
import UniformTypeIdentifiers
import OxydeCore

extension UTType {
    static let oxydeTheme = UTType(exportedAs: ThemeCodec.uniformTypeIdentifier, conformingTo: .json)
}

/// Map Studio: preview every theme on the live map, apply it, assign it to day, night or
/// CarPlay, and create, import, export or share custom themes.
struct MapStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeStore.self) private var themes
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var previewTheme: MapTheme?
    @State private var editing: MapTheme?
    @State private var importing = false
    @State private var message: String?
    @State private var showPremium = false

    private var center: Coordinate {
        location.lastFix?.coordinate ?? Coordinate(latitude: 48.8584, longitude: 2.2945)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    livePreview
                    engineRow
                    ForEach(ThemeFamily.allCases) { family in
                        let list = themes.themes(in: family)
                        if !list.isEmpty || family == .custom {
                            section(family, list)
                        }
                    }
                }
                .padding(.horizontal, OX.gutter)
                .padding(.bottom, 30)
            }
            .navigationTitle("Map Studio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.oxydeTheme, .json]) { result in
                importTheme(result)
            }
            .sheet(item: $editing) { t in ThemeEditorView(theme: t) }
            .sheet(isPresented: $showPremium) { PremiumView() }
            .alert("Map Studio", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    // MARK: Preview

    private var shown: MapTheme { previewTheme ?? model.activeTheme }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            OxydeMapView(engine: model.engine(for: shown), surface: .preview,
                         state: MapSceneState(theme: shown, nightActive: model.nightActive, settings: settings.value,
                                              cameraCenter: center))
                .id(model.engine(for: shown))
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: OX.corner, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shown.name).font(.headline)
                        Text(shown.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(12)
                    .oxPanel(.glass, cornerRadius: 14)
                    .padding(10)
                }
            if previewTheme != nil, previewTheme?.id != model.activeTheme.id {
                HStack {
                    Button("Apply \(shown.name)") { apply(shown) }.buttonStyle(PrimaryButtonStyle())
                    Button("Cancel") { previewTheme = nil }.buttonStyle(SecondaryButtonStyle()).frame(width: 110)
                }
            }
        }
        .padding(.top, 8)
    }

    private var engineRow: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 6) {
            Picker("Map engine", selection: $settings.value.mapEngine) {
                ForEach(MapEngine.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!model.configuration.vectorEngineAvailable)
            Text(engineNote).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var engineNote: String {
        if model.configuration.vectorEngineAvailable {
            return settings.value.mapEngine == .vector
                ? "Vector engine: every color, road shape and label style renders. Satellite looks switch to Apple Maps automatically."
                : "Apple Maps engine: base map, emphasis, 3D, points of interest, traffic, route and camera styling apply. Custom map colors need the vector engine."
        }
        return "Apple Maps engine. Base map, emphasis, 3D, points of interest, traffic, route and camera settings apply. Custom road, land and water colors need the vector engine, which isn't set up in this build (see docs/PROVIDERS.md)."
    }

    // MARK: Gallery

    private func section(_ family: ThemeFamily, _ list: [MapTheme]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(family.title).font(.title3.bold())
                Spacer()
                if family == .custom {
                    Button { editing = model.activeTheme.duplicated(named: "My \(model.activeTheme.name.replacingOccurrences(of: "Oxyde ", with: ""))") } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            if list.isEmpty {
                Text("Duplicate any theme to start your own.").font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(list) { t in card(t) }
            }
        }
    }

    private func card(_ t: MapTheme) -> some View {
        let locked = t.isPremium && !model.premium.isUnlocked
        let active = model.activeTheme.id == t.id
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) { previewTheme = t }
            model.haptics.tap(enabled: settings.value.hapticsEnabled)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ThemeThumbnail(theme: t, engine: model.engine(for: t), nightActive: model.nightActive, center: center)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if locked { Image(systemName: "lock.fill").padding(6).background(.ultraThinMaterial, in: Circle()).padding(6) }
                        else if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).padding(8) }
                    }
                Text(t.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(t.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(8)
            .background(OX.surface, in: RoundedRectangle(cornerRadius: OX.radiusLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: OX.radiusLarge, style: .continuous)
                .strokeBorder(active ? Color.accentColor : OX.line, lineWidth: active ? 2 : 1))
        }
        .buttonStyle(OxCardButtonStyle())
        .accessibilityIdentifier("studio.theme.\(t.id)")
        .contextMenu { actions(for: t, locked: locked) }
    }

    @ViewBuilder
    private func actions(for t: MapTheme, locked: Bool) -> some View {
        if locked {
            Button("Unlock with Premium", systemImage: "lock.open") { showPremium = true }
        } else {
            Button("Apply", systemImage: "checkmark") { apply(t) }
            Button("Use for Day", systemImage: "sun.max") { settings.value.dayThemeID = t.id }
            Button("Use for Night", systemImage: "moon") { settings.value.nightThemeID = t.id }
            Button("Use in CarPlay", systemImage: "car") { settings.value.carPlayThemeID = t.id }
        }
        Button("Duplicate and Edit", systemImage: "slider.horizontal.3") { editing = t.duplicated(named: "My \(t.name.replacingOccurrences(of: "Oxyde ", with: ""))") }
        if t.family == .custom {
            Button("Edit", systemImage: "pencil") { editing = t }
            if let url = try? themes.exportFile(for: t) {
                ShareLink(item: url) { Label("Export File", systemImage: "doc") }
            }
            if let link = try? ThemeCodec.shareLink(for: t) {
                ShareLink(item: link) { Label("Share Link", systemImage: "link") }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { themes.delete(t) }
        }
    }

    private func apply(_ t: MapTheme) {
        if t.isPremium && !model.premium.isUnlocked { showPremium = true; return }
        settings.value.defaultThemeID = t.id
        settings.value.dayThemeID = t.id
        // A dark theme applied by hand should also hold at night.
        if t.appearance != .light { settings.value.nightThemeID = t.id }
        settings.value.cameraMode = t.camera.mode
        settings.value.activeProfileID = nil
        model.play.record(.themeApplied(id: t.id))
        previewTheme = nil
        model.haptics.success(enabled: settings.value.hapticsEnabled)
    }

    private func importTheme(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e): message = e.localizedDescription
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let t = try ThemeCodec.importData(Data(contentsOf: url))
                themes.save(t)
                message = "Added “\(t.name)” to My Themes."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// A real MapKit snapshot of the theme's base configuration with its route color drawn
/// on top as a sample line, so cards show what the map will actually look like.
struct ThemeThumbnail: View {
    let theme: MapTheme
    var engine: MapEngine = .appleMaps
    let nightActive: Bool
    let center: Coordinate
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(hex: theme.resolvedPalette(nightActive: nightActive).background)
            if let image { Image(uiImage: image).resizable().scaledToFill().transition(.opacity) }
            routeSample
        }
        .animation(.easeOut(duration: 0.35), value: image != nil)
        .task(id: theme) {
            image = await ThemeSnapshotCache.shared.image(for: theme, engine: engine, nightActive: nightActive, center: center,
                                                         size: CGSize(width: 340, height: 220))
        }
    }

    private var routeSample: some View {
        let r = theme.resolvedRoute(nightActive: nightActive)
        return GeometryReader { g in
            let path = Path { p in
                p.move(to: CGPoint(x: g.size.width * 0.12, y: g.size.height * 0.85))
                p.addCurve(to: CGPoint(x: g.size.width * 0.88, y: g.size.height * 0.2),
                           control1: CGPoint(x: g.size.width * 0.5, y: g.size.height * 0.9),
                           control2: CGPoint(x: g.size.width * 0.45, y: g.size.height * 0.15))
            }
            ZStack {
                if r.glow > 0 { path.stroke(Color(hex: r.glowColor).opacity(0.35 * r.glow), style: StrokeStyle(lineWidth: r.width * 0.6 * 2.6, lineCap: .round)).blur(radius: 3) }
                if r.casingWidth > 0 { path.stroke(Color(hex: r.casingColor), style: StrokeStyle(lineWidth: (r.width + r.casingWidth * 2) * 0.6, lineCap: .round)) }
                path.stroke(Color(hex: r.color), style: StrokeStyle(lineWidth: r.width * 0.6, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}
