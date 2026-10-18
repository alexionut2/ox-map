import SwiftUI
import OxydeCore

/// The custom theme editor. Every control edits a real `MapTheme` property; each one is
/// labeled with whether the current map engine renders it.
struct ThemeEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeStore.self) private var themes
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var draft: MapTheme
    @State private var editNight = false
    private let original: MapTheme

    init(theme: MapTheme) {
        _draft = State(initialValue: theme)
        original = theme
    }

    private var engine: MapEngine { model.activeEngine }

    private func support(_ p: ThemeProperty) -> PropertySupport { RendererCapabilities.support(p, on: engine) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OxydeMapView(engine: engine, surface: .preview,
                             state: MapSceneState(theme: draft, nightActive: editNight, settings: settings.value,
                                                  cameraCenter: location.lastFix?.coordinate ?? Coordinate(latitude: 48.8584, longitude: 2.2945)))
                    .frame(height: 200)
                    .overlay(alignment: .bottomTrailing) {
                        ThemeThumbnailRoute(route: draft.resolvedRoute(nightActive: editNight)).frame(width: 120, height: 60).padding(10)
                    }
                Form {
                    Section("Name") {
                        TextField("Theme name", text: $draft.name).accessibilityIdentifier("editor.name")
                    }
                    baseMapSection
                    routeSection
                    cameraSection
                    paletteSection
                    trafficSection
                    interfaceSection
                    carPlaySection
                    Section {
                        Button("Restore Defaults", role: .destructive) { restore() }
                            .disabled(themes.original(of: draft) == nil)
                    } footer: {
                        Text(themes.original(of: draft).map { "Resets every setting to \($0.name)." } ?? "")
                    }
                }
            }
            .navigationTitle("Edit Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().accessibilityIdentifier("editor.save")
                }
            }
        }
    }

    // MARK: Sections

    private var baseMapSection: some View {
        Section {
            row("Base map", .baseMap) {
                Picker("Base map", selection: $draft.baseMap) {
                    Text("Streets").tag(BaseMap.standard)
                    Text("Satellite").tag(BaseMap.satellite)
                    Text("Hybrid").tag(BaseMap.hybrid)
                }
            }
            row("Appearance", .appearance) {
                Picker("Appearance", selection: $draft.appearance) {
                    Text("Light").tag(MapAppearance.light)
                    Text("Dark").tag(MapAppearance.dark)
                    Text("Day/Night").tag(MapAppearance.automatic)
                }
            }
            row("Emphasis", .emphasis) {
                Picker("Emphasis", selection: $draft.emphasis) {
                    Text("Standard").tag(MapEmphasis.standard)
                    Text("Muted").tag(MapEmphasis.muted)
                }
            }
            row("Elevation", .elevation) {
                Picker("Elevation", selection: $draft.elevation) {
                    Text("Flat").tag(MapElevation.flat)
                    Text("Realistic 3D").tag(MapElevation.realistic)
                }
            }
            row("Buildings", .buildings3D) { Toggle("Buildings", isOn: $draft.showsBuildings) }
            row("Points of interest", .poiVisibility) {
                Picker("Points of interest", selection: $draft.poiVisibility) {
                    Text("All").tag(POIVisibility.all)
                    Text("Driving").tag(POIVisibility.driving)
                    Text("None").tag(POIVisibility.none)
                }
            }
            row("Traffic", .traffic) { Toggle("Traffic", isOn: $draft.showsTraffic) }
            row("Terrain shading", .hillshade) { Toggle("Terrain shading", isOn: $draft.showsHillshade) }
        } header: {
            Text("Map")
        }
    }

    private var routeSection: some View {
        Section {
            Toggle("Edit night route", isOn: $editNight).disabled(draft.appearance != .automatic)
            let binding = routeBinding
            color("Route", binding.color, .routeColor)
            color("Alternate routes", binding.alternateColor, .alternateRouteColor)
            color("Driven part", binding.traveledColor, .routeColor)
            slider("Width", binding.width, 2...16, .routeWidth)
            color("Casing", binding.casingColor, .routeCasing)
            slider("Casing width", binding.casingWidth, 0...6, .routeCasing)
            slider("Glow", binding.glow, 0...1, .routeGlow)
            color("Glow color", binding.glowColor, .routeGlow)
        } header: {
            Text("Route line")
        } footer: {
            Text("Oxyde draws the route itself, so these apply on every engine. CarPlay drops the glow to keep the car display calm.")
        }
    }

    private var cameraSection: some View {
        Section("Navigation camera") {
            row("Default view", .cameraMode) {
                Picker("Default view", selection: $draft.camera.mode) {
                    ForEach(CameraMode.allCases) { Text($0.title).tag($0) }
                }
            }
            slider("Tilt", $draft.camera.pitch, 0...75, .cameraPitch, format: "%.0f°")
            slider("Distance", $draft.camera.distance, 250...2000, .cameraDistance, format: "%.0f m")
        }
    }

    private var paletteSection: some View {
        let p = paletteBinding
        return Section {
            if engine == .appleMaps {
                Text("Apple Maps doesn't allow custom map colors. These are saved with the theme, used by the vector engine and included when you export or share.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            color("Background", p.background, .backgroundColor)
            color("Land", p.land, .landColor)
            color("Parks", p.park, .parkColor)
            color("Water", p.water, .waterColor)
            color("Highways", p.roadHighway, .roadColors)
            color("Major roads", p.roadMajor, .roadColors)
            color("Minor roads", p.roadMinor, .roadColors)
            color("Road edges", p.roadCasing, .roadColors)
            slider("Road thickness", p.roadWidthScale, 0.5...2, .roadWidth, format: "%.1f×")
            color("Buildings", p.building, .buildingColors)
            color("3D buildings", p.buildingExtrusion, .buildingColors)
            color("Labels", p.label, .labelColors)
            color("Label outline", p.labelHalo, .labelColors)
            slider("Label size", p.labelSizeScale, 0.7...1.6, .labelSize, format: "%.1f×")
            row("Label density", .labelDensity) {
                Picker("Label density", selection: p.labelDensity) {
                    ForEach(LabelDensity.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
            }
            labelContrastNote(p.wrappedValue)
        } header: {
            HStack { Text(editNight ? "Map colors (night)" : "Map colors"); Spacer(); SupportBadge(support: support(.landColor)) }
        }
    }

    private var trafficSection: some View {
        let p = paletteBinding
        return Section {
            color("Free flow", p.trafficFree, .trafficColors)
            color("Slow", p.trafficModerate, .trafficColors)
            color("Heavy", p.trafficHeavy, .trafficColors)
            color("Closed", p.trafficClosed, .trafficColors)
        } header: {
            Text("Traffic colors")
        } footer: {
            Text("Apple Maps draws traffic in its own colors. These apply to the vector engine.")
        }
    }

    private var interfaceSection: some View {
        Section("Interface") {
            color("Accent", $draft.interface.accent, .accent)
            Picker("Panels", selection: $draft.interface.panel) {
                Text("Glass").tag(PanelStyle.glass)
                Text("Solid").tag(PanelStyle.solid)
            }
            Picker("Typography", selection: $draft.interface.typography) {
                ForEach(TypographyStyle.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Maneuver panel", selection: $draft.interface.maneuverPanel) {
                Text("Standard").tag(ManeuverPanelStyle.standard)
                Text("Cockpit").tag(ManeuverPanelStyle.cockpit)
            }
        }
    }

    private var carPlaySection: some View {
        Section {
            ColorPicker("Route color", selection: hex($draft.carPlay.routeColor), supportsOpacity: false)
            slider("Route width", $draft.carPlay.routeWidth, 4...14, .routeWidth)
            Toggle("Always dark", isOn: $draft.carPlay.alwaysDark)
            Toggle("Traffic", isOn: $draft.carPlay.showsTraffic)
            let contrast = HexColor.contrast(draft.carPlay.routeColor, draft.palette.roadMajor)
            if contrast < 3 {
                Label("This route color is hard to see against the roads. CarPlay needs high contrast.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("CarPlay")
        } footer: {
            Text("The car display gets a simplified version of the theme: high-contrast route, no decorative effects.")
        }
    }

    // MARK: Bindings

    private var routeBinding: Binding<RouteStyle> {
        Binding(get: { editNight ? (draft.nightRoute ?? draft.route) : draft.route },
                set: { if editNight { draft.nightRoute = $0 } else { draft.route = $0 } })
    }

    private var paletteBinding: Binding<VectorPalette> {
        Binding(get: { editNight ? (draft.nightPalette ?? draft.palette) : draft.palette },
                set: { if editNight { draft.nightPalette = $0 } else { draft.palette = $0 } })
    }

    private func hex(_ b: Binding<HexColor>) -> Binding<Color> {
        Binding(get: { Color(hex: b.wrappedValue) }, set: { b.wrappedValue = HexColor($0) })
    }

    // MARK: Rows

    private func row<Content: View>(_ title: String, _ p: ThemeProperty, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
            SupportBadge(support: support(p))
        }
    }

    private func color(_ title: String, _ b: Binding<HexColor>, _ p: ThemeProperty) -> some View {
        HStack {
            ColorPicker(title, selection: hex(b), supportsOpacity: false)
            SupportBadge(support: support(p))
        }
    }

    private func slider(_ title: String, _ b: Binding<Double>, _ range: ClosedRange<Double>, _ p: ThemeProperty, format: String = "%.1f") -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, b.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
                SupportBadge(support: support(p))
            }
            Slider(value: b, in: range)
        }
    }

    @ViewBuilder
    private func labelContrastNote(_ p: VectorPalette) -> some View {
        let c = HexColor.contrast(p.label, p.land)
        if c < 3 {
            Label("Labels may be hard to read on this land color (contrast \(String(format: "%.1f", c)):1).", systemImage: "eye.trianglebadge.exclamationmark")
                .font(.footnote).foregroundStyle(.orange)
        }
    }

    // MARK: Actions

    private func restore() {
        guard let base = themes.original(of: draft) else { return }
        let keepID = draft.id, keepName = draft.name
        draft = base.duplicated(named: keepName, id: keepID)
    }

    private func save() {
        var t = draft
        t.name = t.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.name.isEmpty { t.name = "My Theme" }
        if t.family != .custom { t = t.duplicated(named: t.name) }
        if t.appearance == .automatic, t.nightPalette == nil { t.nightPalette = t.palette }
        themes.save(t)
        settings.value.defaultThemeID = t.id
        settings.value.dayThemeID = t.id
        if t.appearance != .light { settings.value.nightThemeID = t.id }
        dismiss()
    }
}

/// A small route-line sample so route edits are visible even before a route exists.
struct ThemeThumbnailRoute: View {
    let route: RouteStyle
    var body: some View {
        GeometryReader { g in
            let path = Path { p in
                p.move(to: CGPoint(x: 8, y: g.size.height - 8))
                p.addQuadCurve(to: CGPoint(x: g.size.width - 8, y: 8), control: CGPoint(x: g.size.width * 0.2, y: 0))
            }
            ZStack {
                if route.glow > 0 { path.stroke(Color(hex: route.glowColor).opacity(0.4 * route.glow), style: StrokeStyle(lineWidth: route.width * 2.6, lineCap: .round)).blur(radius: 3) }
                if route.casingWidth > 0 { path.stroke(Color(hex: route.casingColor), style: StrokeStyle(lineWidth: route.width + route.casingWidth * 2, lineCap: .round)) }
                path.stroke(Color(hex: route.color), style: StrokeStyle(lineWidth: route.width, lineCap: .round))
            }
        }
        .padding(6)
        .oxPanel(.glass, cornerRadius: 12)
        .accessibilityHidden(true)
    }
}
