import XCTest
@testable import OxydeCore

final class ThemeTests: XCTestCase {
    let config = VectorTileConfiguration(vectorTileJSONURL: "https://tiles.example/tiles.json?key=K",
                                         glyphsURL: "https://tiles.example/fonts/{fontstack}/{range}.pbf",
                                         imageryTileURL: "https://tiles.example/sat/{z}/{x}/{y}.jpg",
                                         terrainTileJSONURL: "https://tiles.example/terrain.json",
                                         attribution: "© Example")

    func testRegistryHasAllFifteenThemesWithUniqueIDs() {
        let all = ThemeRegistry.all
        XCTAssertEqual(all.count, 15)
        XCTAssertEqual(Set(all.map(\.id)).count, 15)
        XCTAssertEqual(ThemeRegistry.themes(in: .essential).count, 7)
        XCTAssertEqual(ThemeRegistry.themes(in: .automotive).count, 4)
        XCTAssertEqual(ThemeRegistry.themes(in: .futuristic).count, 4)
        XCTAssertNotNil(ThemeRegistry.theme(id: ThemeRegistry.defaultThemeID))
        XCTAssertNotNil(ThemeRegistry.theme(id: ThemeRegistry.defaultNightThemeID))
        XCTAssertNotNil(ThemeRegistry.theme(id: ThemeRegistry.defaultDayThemeID))
    }

    func testThemesAreGenuinelyDifferentConfigurations() {
        // Each theme must differ from every other in more than its name.
        let all = ThemeRegistry.all
        for (i, a) in all.enumerated() {
            for b in all[(i + 1)...] {
                var x = a, y = b
                x.id = ""; y.id = ""; x.name = ""; y.name = ""; x.summary = ""; y.summary = ""
                x.family = .custom; y.family = .custom; x.isPremium = false; y.isPremium = false
                XCTAssertNotEqual(x, y, "\(a.id) and \(b.id) render identically")
            }
        }
    }

    func testRouteIsVisibleAgainstMapInEveryTheme() {
        for t in ThemeRegistry.all {
            for night in [false, true] {
                let palette = t.resolvedPalette(nightActive: night)
                let route = t.resolvedRoute(nightActive: night)
                let contrast = HexColor.contrast(route.color, palette.roadMajor)
                XCTAssertGreaterThanOrEqual(contrast, 2.5, "\(t.id) night=\(night) route contrast \(contrast)")
            }
        }
    }

    func testHexColorParsingAndFormatting() {
        XCTAssertEqual(HexColor(hex: "#1E88FF")?.hexString, "#1E88FF")
        XCTAssertEqual(HexColor(hex: "fff")?.hexString, "#FFFFFF")
        XCTAssertEqual(HexColor(hex: "#00000080")?.alpha ?? 0, 128.0 / 255, accuracy: 0.001)
        XCTAssertNil(HexColor(hex: "#12"))
        XCTAssertNil(HexColor(hex: "zzzzzz"))
        XCTAssertEqual(HexColor.contrast("#000000", "#FFFFFF"), 21, accuracy: 0.01)
        XCTAssertEqual(HexColor(hex: "#FF0000")!.cssRGBA, "rgba(255, 0, 0, 1.00)")
    }

    func testExportImportRoundTripAssignsNewIdentity() throws {
        let original = ThemeRegistry.theme(id: "oxyde.neon")!
        let data = try ThemeCodec.exportData(original)
        let imported = try ThemeCodec.importData(data)
        XCTAssertNotEqual(imported.id, original.id)
        XCTAssertTrue(imported.id.hasPrefix("custom-"))
        XCTAssertEqual(imported.family, .custom)
        XCTAssertFalse(imported.isPremium)
        XCTAssertEqual(imported.route, original.route)
        XCTAssertEqual(imported.palette, original.palette)
        XCTAssertEqual(imported.name, original.name)
    }

    func testImportClampsHostileValues() throws {
        var t = ThemeRegistry.theme(id: "oxyde.dark")!
        t.route.width = 400
        t.route.glow = -3
        t.camera.pitch = 120
        t.palette.roadWidthScale = 50
        t.name = String(repeating: "x", count: 500)
        let imported = try ThemeCodec.importData(ThemeCodec.exportData(t))
        XCTAssertEqual(imported.route.width, 16)
        XCTAssertEqual(imported.route.glow, 0)
        XCTAssertEqual(imported.camera.pitch, 75)
        XCTAssertEqual(imported.palette.roadWidthScale, 2)
        XCTAssertEqual(imported.name.count, 40)
    }

    func testImportRejectsNonThemesAndNewerVersions() throws {
        XCTAssertThrowsError(try ThemeCodec.importData(Data("{\"hello\":1}".utf8))) {
            XCTAssertEqual($0 as? ThemeCodecError, .notAThemeFile)
        }
        var t = ThemeRegistry.theme(id: "oxyde.dark")!
        t.schemaVersion = 99
        XCTAssertThrowsError(try ThemeCodec.importData(ThemeCodec.exportData(t))) {
            XCTAssertEqual($0 as? ThemeCodecError, .unsupportedVersion(99))
        }
        XCTAssertThrowsError(try ThemeCodec.importData(Data(count: 100_000))) {
            XCTAssertEqual($0 as? ThemeCodecError, .tooLarge)
        }
    }

    func testShareLinkRoundTrip() throws {
        let t = ThemeRegistry.theme(id: "oxyde.synthwave")!
        let url = try ThemeCodec.shareLink(for: t)
        XCTAssertEqual(url.scheme, "oxydemap")
        XCTAssertEqual(url.host, "theme")
        let back = try ThemeCodec.theme(fromLink: url)
        XCTAssertEqual(back.route, t.route)
        XCTAssertThrowsError(try ThemeCodec.theme(fromLink: URL(string: "oxydemap://theme?d=!!!")!))
        XCTAssertThrowsError(try ThemeCodec.theme(fromLink: URL(string: "https://example.com")!))
    }

    func testDuplicateKeepsLineage() {
        let base = ThemeRegistry.theme(id: "oxyde.luxury")!
        let copy = base.duplicated(named: "Mine")
        XCTAssertEqual(copy.basedOn, "oxyde.luxury")
        XCTAssertEqual(copy.family, .custom)
        XCTAssertEqual(copy.duplicated(named: "Again").basedOn, "oxyde.luxury")
    }

    func testCapabilitiesAreHonestAboutAppleMaps() {
        XCTAssertFalse(RendererCapabilities.support(.roadColors, on: .appleMaps).isUsable)
        XCTAssertFalse(RendererCapabilities.support(.waterColor, on: .appleMaps).isUsable)
        XCTAssertTrue(RendererCapabilities.support(.routeGlow, on: .appleMaps).isUsable)
        XCTAssertEqual(RendererCapabilities.support(.emphasis, on: .appleMaps), .supported)
        for p in ThemeProperty.allCases {
            XCTAssertTrue(RendererCapabilities.support(p, on: .vector).isUsable, "\(p)")
        }
    }

    // MARK: Vector style

    func layerIDs(_ style: JSONValue) -> [String] {
        style["layers"]?.arrayValue?.compactMap { $0["id"]?.stringValue } ?? []
    }

    func layer(_ style: JSONValue, _ id: String) -> JSONValue? {
        style["layers"]?.arrayValue?.first { $0["id"]?.stringValue == id }
    }

    func testVectorStyleUsesThemePalette() throws {
        let theme = ThemeRegistry.theme(id: "oxyde.neon")!
        let style = VectorStyleBuilder.style(for: theme, nightActive: false, configuration: config)
        XCTAssertEqual(style["version"]?.numberValue, 8)
        XCTAssertEqual(layer(style, "water")?["paint"]?["fill-color"]?.stringValue, theme.palette.water.cssRGBA)
        XCTAssertEqual(layer(style, "road-highway")?["paint"]?["line-color"]?.stringValue, theme.palette.roadHighway.cssRGBA)
        XCTAssertEqual(layer(style, "route")?["paint"]?["line-color"]?.stringValue, theme.route.color.cssRGBA)
        XCTAssertNotNil(layer(style, "route-glow"))
        // Labels are drawn above the route.
        let ids = layerIDs(style)
        XCTAssertLessThan(ids.firstIndex(of: "route")!, ids.firstIndex(of: "label-place")!)
        XCTAssertNotNil(try? style.data())
    }

    func testVectorStyleBuildingsAndTerrain() {
        let terrain = ThemeRegistry.theme(id: "oxyde.terrain")!
        let s = VectorStyleBuilder.style(for: terrain, nightActive: false, configuration: config)
        XCTAssertNotNil(layer(s, "building-3d"))
        XCTAssertNotNil(layer(s, "hillshade"))
        let minimal = ThemeRegistry.theme(id: "oxyde.minimal")!
        let m = VectorStyleBuilder.style(for: minimal, nightActive: false, configuration: config)
        XCTAssertNil(layer(m, "building-3d"))
        XCTAssertNil(layer(m, "building"))
        XCTAssertNil(layer(m, "label-poi"))
        XCTAssertNil(layer(m, "route-glow"))
    }

    func testVectorStyleNightPaletteAndDensity() {
        let classic = ThemeRegistry.theme(id: "oxyde.classic")!
        let night = VectorStyleBuilder.style(for: classic, nightActive: true, configuration: config)
        XCTAssertEqual(layer(night, "background")?["paint"]?["background-color"]?.stringValue, classic.nightPalette!.background.cssRGBA)
        var none = classic
        none.palette.labelDensity = .none
        XCTAssertFalse(layerIDs(VectorStyleBuilder.style(for: none, nightActive: false, configuration: config)).contains { $0.hasPrefix("label") })
    }

    func testVectorStyleImageryForHybridAndSatellite() {
        let sat = ThemeRegistry.theme(id: "oxyde.satellite")!
        let hybrid = VectorStyleBuilder.style(for: sat, nightActive: false, configuration: config)
        XCTAssertNotNil(layer(hybrid, "imagery"))
        XCTAssertNotNil(layer(hybrid, "road-primary"))
        var pure = sat
        pure.baseMap = .satellite
        let p = VectorStyleBuilder.style(for: pure, nightActive: false, configuration: config)
        XCTAssertNil(layer(p, "road-primary"))
        XCTAssertFalse(layerIDs(p).contains { $0.hasPrefix("label") })
        var noImagery = config
        noImagery.imageryTileURL = nil
        XCTAssertNil(layer(VectorStyleBuilder.style(for: sat, nightActive: false, configuration: noImagery), "imagery"))
    }

    func testRouteGeoJSON() {
        let g = VectorStyleBuilder.routeGeoJSON(remaining: Fixtures.lRoute().coordinates, traveled: [], alternates: [[Fixtures.origin]])
        XCTAssertEqual(g["features"]?.arrayValue?.count, 1)
        XCTAssertEqual(g["features"]?.arrayValue?.first?["properties"]?["role"]?.stringValue, "primary")
    }
}
