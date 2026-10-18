import Foundation

/// Where the vector engine gets its data. Every URL comes from the app's configuration
/// (Config/Secrets.xcconfig); nothing is hardcoded to a provider.
public struct VectorTileConfiguration: Codable, Hashable, Sendable {
    /// TileJSON URL for an OpenMapTiles-schema vector source, for example
    /// `https://api.maptiler.com/tiles/v3/tiles.json?key=…`.
    public var vectorTileJSONURL: String
    /// Glyph URL template with `{fontstack}` and `{range}`.
    public var glyphsURL: String
    public var fontStack: [String]
    /// Optional raster imagery tile template (`{z}/{x}/{y}`), for Satellite and Hybrid.
    public var imageryTileURL: String?
    /// Optional TileJSON URL for a raster-dem terrain source, for hillshading.
    public var terrainTileJSONURL: String?
    public var attribution: String

    public init(vectorTileJSONURL: String, glyphsURL: String, fontStack: [String] = ["Noto Sans Regular"],
                imageryTileURL: String? = nil, terrainTileJSONURL: String? = nil, attribution: String) {
        self.vectorTileJSONURL = vectorTileJSONURL
        self.glyphsURL = glyphsURL
        self.fontStack = fontStack
        self.imageryTileURL = imageryTileURL
        self.terrainTileJSONURL = terrainTileJSONURL
        self.attribution = attribution
    }

    public var isComplete: Bool { !vectorTileJSONURL.isEmpty && !glyphsURL.isEmpty }
}

/// Compiles a `MapTheme` into a MapLibre style document (style spec v8) for an
/// OpenMapTiles-schema tile source. This is how the Studio's road, land, water, building
/// and label settings become real rendering rules rather than a tint over the map.
public enum VectorStyleBuilder {
    public static let routeSourceID = "oxyde-route"
    public static let incidentSourceID = "oxyde-incidents"

    public static func style(for theme: MapTheme, nightActive: Bool, configuration: VectorTileConfiguration) -> JSONValue {
        let p = theme.resolvedPalette(nightActive: nightActive)
        var sources: [String: JSONValue] = [
            "openmaptiles": ["type": "vector", "url": .string(configuration.vectorTileJSONURL),
                             "attribution": .string(configuration.attribution)]
        ]
        let usesImagery = theme.baseMap != .standard && configuration.imageryTileURL != nil
        if let imagery = configuration.imageryTileURL {
            sources["imagery"] = ["type": "raster", "tiles": [.string(imagery)], "tileSize": 256,
                                  "attribution": .string(configuration.attribution)]
        }
        if theme.showsHillshade, let terrain = configuration.terrainTileJSONURL {
            sources["terrain"] = ["type": "raster-dem", "url": .string(terrain)]
        }

        var layers: [JSONValue] = []
        layers.append(["id": "background", "type": "background", "paint": ["background-color": color(p.background)]])

        if usesImagery {
            layers.append(["id": "imagery", "type": "raster", "source": "imagery"])
        } else {
            layers.append(fill("landcover-park", sourceLayer: "landcover",
                               filter: ["match", ["get", "class"], ["grass", "wood", "farmland"], true, false],
                               color: p.park))
            layers.append(fill("park", sourceLayer: "park", filter: nil, color: p.park))
            layers.append(fill("landuse", sourceLayer: "landuse",
                               filter: ["match", ["get", "class"], ["residential", "suburb", "neighbourhood"], true, false],
                               color: p.land))
            layers.append(fill("water", sourceLayer: "water", filter: nil, color: p.water))
            if sources["terrain"] != nil {
                layers.append(["id": "hillshade", "type": "hillshade", "source": "terrain",
                               "paint": ["hillshade-shadow-color": color(p.label.withAlpha(0.35)),
                                         "hillshade-highlight-color": color(p.labelHalo.withAlpha(0.25)),
                                         "hillshade-exaggeration": 0.4]])
            }
            if theme.showsBuildings {
                if theme.elevation == .realistic {
                    layers.append(["id": "building-3d", "type": "fill-extrusion", "source": "openmaptiles",
                                   "source-layer": "building", "minzoom": 14,
                                   "paint": ["fill-extrusion-color": color(p.buildingExtrusion),
                                             "fill-extrusion-height": ["coalesce", ["get", "render_height"], 6],
                                             "fill-extrusion-base": ["coalesce", ["get", "render_min_height"], 0],
                                             "fill-extrusion-opacity": 0.85]])
                } else {
                    layers.append(["id": "building", "type": "fill", "source": "openmaptiles",
                                   "source-layer": "building", "minzoom": 13,
                                   "paint": ["fill-color": color(p.building)]])
                }
            }
        }

        // Roads are drawn for Standard and Hybrid; Satellite is imagery only.
        if theme.baseMap != .satellite || !usesImagery {
            let alpha = usesImagery ? 0.75 : 1.0
            let classes: [(String, [String], HexColor, Double)] = [
                ("minor", ["minor", "service", "track"], p.roadMinor, 0.6),
                ("secondary", ["secondary", "tertiary"], p.roadMajor, 0.85),
                ("primary", ["primary", "trunk"], p.roadMajor, 1.0),
                ("highway", ["motorway"], p.roadHighway, 1.25),
            ]
            for (name, cls, _, weight) in classes {
                layers.append(road("road-\(name)-casing", classes: cls, color: p.roadCasing.withAlpha(alpha),
                                   width: weight * p.roadWidthScale * 1.35))
            }
            for (name, cls, c, weight) in classes {
                layers.append(road("road-\(name)", classes: cls, color: c.withAlpha(alpha), width: weight * p.roadWidthScale))
            }
        }

        // Route and incident layers sit above roads, below labels. The app fills these
        // sources with the active route and incidents.
        let route = theme.resolvedRoute(nightActive: nightActive)
        let routeFilter: JSONValue = ["==", ["get", "role"], "primary"]
        let altFilter: JSONValue = ["==", ["get", "role"], "alternate"]
        let traveledFilter: JSONValue = ["==", ["get", "role"], "traveled"]
        layers.append(line("route-alternate", source: routeSourceID, filter: altFilter, color: route.alternateColor, width: route.width * 0.8))
        layers.append(line("route-traveled", source: routeSourceID, filter: traveledFilter, color: route.traveledColor, width: route.width))
        if route.glow > 0 {
            layers.append(["id": "route-glow", "type": "line", "source": .string(routeSourceID), "filter": routeFilter,
                           "layout": ["line-cap": "round", "line-join": "round"],
                           "paint": ["line-color": color(route.glowColor), "line-width": .number(route.width * 3.2),
                                     "line-blur": .number(route.width * 1.6), "line-opacity": .number(0.55 * route.glow)]])
        }
        if route.casingWidth > 0 {
            layers.append(line("route-casing", source: routeSourceID, filter: routeFilter, color: route.casingColor,
                               width: route.width + route.casingWidth * 2))
        }
        layers.append(line("route", source: routeSourceID, filter: routeFilter, color: route.color, width: route.width))
        layers.append(["id": "incidents", "type": "circle", "source": .string(incidentSourceID),
                       "paint": ["circle-radius": 7, "circle-color": color(p.trafficHeavy),
                                 "circle-stroke-color": color(p.labelHalo), "circle-stroke-width": 2]])

        layers.append(contentsOf: labelLayers(theme: theme, palette: p, fonts: configuration.fontStack))

        let style: JSONValue = .object([
            "version": 8,
            "name": .string(theme.name),
            "glyphs": .string(configuration.glyphsURL),
            "sources": .object(sources.merging([
                routeSourceID: ["type": "geojson", "data": ["type": "FeatureCollection", "features": []]],
                incidentSourceID: ["type": "geojson", "data": ["type": "FeatureCollection", "features": []]],
            ], uniquingKeysWith: { a, _ in a })),
            "layers": .array(layers),
        ])
        return style
    }

    // MARK: Layer helpers

    static func color(_ c: HexColor) -> JSONValue { .string(c.cssRGBA) }

    static func fill(_ id: String, sourceLayer: String, filter: JSONValue?, color c: HexColor) -> JSONValue {
        var o: [String: JSONValue] = ["id": .string(id), "type": "fill", "source": "openmaptiles",
                                      "source-layer": .string(sourceLayer), "paint": ["fill-color": color(c)]]
        if let filter { o["filter"] = filter }
        return .object(o)
    }

    static func road(_ id: String, classes: [String], color c: HexColor, width: Double) -> JSONValue {
        [
            "id": .string(id), "type": "line", "source": "openmaptiles", "source-layer": "transportation",
            "filter": ["match", ["get", "class"], .array(classes.map { .string($0) }), true, false],
            "layout": ["line-cap": "round", "line-join": "round"],
            "paint": [
                "line-color": color(c),
                "line-width": ["interpolate", ["exponential", 1.5], ["zoom"],
                               5, .number(0.4 * width), 12, .number(2.5 * width), 18, .number(22 * width)],
            ],
        ]
    }

    static func line(_ id: String, source: String, filter: JSONValue, color c: HexColor, width: Double) -> JSONValue {
        [
            "id": .string(id), "type": "line", "source": .string(source), "filter": filter,
            "layout": ["line-cap": "round", "line-join": "round"],
            "paint": ["line-color": color(c), "line-width": .number(width)],
        ]
    }

    static func labelLayers(theme: MapTheme, palette p: VectorPalette, fonts: [String]) -> [JSONValue] {
        let density = p.labelDensity
        guard density != .none, theme.baseMap != .satellite else { return [] }
        let font: JSONValue = .array(fonts.map { .string($0) })
        let name: JSONValue = ["coalesce", ["get", "name:latin"], ["get", "name"]]
        let paint: JSONValue = ["text-color": color(p.label), "text-halo-color": color(p.labelHalo), "text-halo-width": 1.4]
        let s = p.labelSizeScale
        var out: [JSONValue] = []

        if density == .medium || density == .high {
            out.append(["id": "label-road", "type": "symbol", "source": "openmaptiles",
                        "source-layer": "transportation_name", "minzoom": density == .high ? 12 : 13,
                        "layout": ["symbol-placement": "line", "text-field": name, "text-font": font,
                                   "text-size": .number(12 * s)],
                        "paint": paint])
        }
        if theme.poiVisibility != .none, density != .low {
            var o: [String: JSONValue] = [
                "id": "label-poi", "type": "symbol", "source": "openmaptiles", "source-layer": "poi",
                "minzoom": density == .high ? 14 : 15,
                "layout": ["text-field": name, "text-font": font, "text-size": .number(11 * s),
                           "text-anchor": "top", "text-offset": [0, 0.6]],
                "paint": paint,
            ]
            if theme.poiVisibility == .driving {
                o["filter"] = ["match", ["get", "class"],
                               ["fuel", "parking", "charging_station", "hospital", "toilets", "restaurant", "fast_food", "cafe"],
                               true, false]
            }
            out.append(.object(o))
        }
        let placeClasses: [String] = {
            switch density {
            case .low: return ["city", "town"]
            case .medium: return ["city", "town", "village", "suburb"]
            case .high: return ["city", "town", "village", "suburb", "neighbourhood", "hamlet"]
            case .none: return []
            }
        }()
        out.append(["id": "label-place", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
                    "filter": ["match", ["get", "class"], .array(placeClasses.map { .string($0) }), true, false],
                    "layout": ["text-field": name, "text-font": font,
                               "text-size": ["interpolate", ["linear"], ["zoom"], 6, .number(11 * s), 14, .number(16 * s)]],
                    "paint": paint])
        return out
    }

    /// GeoJSON for the route source: the primary route split into traveled and remaining
    /// parts, plus alternates.
    public static func routeGeoJSON(remaining: [Coordinate], traveled: [Coordinate], alternates: [[Coordinate]]) -> JSONValue {
        func feature(_ coords: [Coordinate], role: String) -> JSONValue {
            ["type": "Feature", "properties": ["role": .string(role)],
             "geometry": ["type": "LineString",
                          "coordinates": .array(coords.map { [.number($0.longitude), .number($0.latitude)] })]]
        }
        var features: [JSONValue] = alternates.filter { $0.count > 1 }.map { feature($0, role: "alternate") }
        if traveled.count > 1 { features.append(feature(traveled, role: "traveled")) }
        if remaining.count > 1 { features.append(feature(remaining, role: "primary")) }
        return ["type": "FeatureCollection", "features": .array(features)]
    }
}
