# Map and data providers

## Decision: Apple MapKit is the primary provider

| Need | Apple MapKit | Mapbox | Google | TomTom / HERE |
|---|---|---|---|---|
| Map, search, routing, traffic layer | Yes, no key | Yes, key | Maps SDK yes; turn-by-turn SDK is restricted | Yes, key |
| Cost | Free | Usage-based | Usage-based | Usage-based |
| CarPlay | Native, Apple's own path | Supported | Navigation SDK terms restrict | Supported |
| Traffic-aware ETAs | Yes | Yes | Yes | Yes |
| Lane guidance, speed limits | No | Yes | Yes | Yes |
| Custom map colors | No | Yes | Partial (cloud styling) | Yes |
| Incident feed (accidents, closures) | No public API | Limited | No public API | **Yes** |

Why MapKit:

1. **No keys or bills to get started.** A Windows user with an iPhone can install and drive with it today.
2. **Real traffic-aware routing and ETAs** from Apple, with no simulated data.
3. **CarPlay** works with the MapKit view on the car display with no extra licensing.
4. Search and autocomplete are good and free.

What MapKit doesn't provide, and how the app handles it:

- **Lane guidance and speed limits:** shown as "Provider limit" in Diagnostics. The data model (`LaneInfo`, `RouteStep.lanes`) and the lane UI are in place for a provider that supplies them. The speedometer shows only your speed, never a guessed limit.
- **Incidents (accidents, closures, roadworks):** come from **TomTom Traffic** through the Oxyde backend, so the key stays on the server.
- **Custom map colors:** come from the optional **vector engine** (below).
- **Avoid ferries:** MKDirections has no option, so the toggle is disabled with a note.
- **Offline maps:** MapKit has no download API. The app says so instead of offering a fake "download" button.

Switching the routing provider later only needs a new `RoutingService` implementation (`OxydeCore/Services/ServiceProtocols.swift`). The navigation engine, guidance and UI work on the provider-neutral `Route` model.

## Map engines and what themes can change

Themes are real style configurations. On Apple Maps they set `MKStandardMapConfiguration` / `MKHybridMapConfiguration` / `MKImageryMapConfiguration`, POI filters, traffic, overlay renderers and the camera. On the vector engine, `VectorStyleBuilder` compiles the theme into a complete MapLibre style JSON.

| Theme property | Apple Maps engine | Vector engine |
|---|---|---|
| Base map (standard, satellite, hybrid) | Yes | Needs an imagery source for satellite |
| Light/dark appearance | Yes | Yes |
| Emphasis (default/muted) | Yes | Yes |
| Realistic elevation, 3D buildings | Yes | Yes (fill-extrusion) |
| POI visibility (all, driving, none) | Yes | Yes |
| Traffic layer | Yes | Needs a traffic tile source |
| Hillshade | Partial (realistic elevation) | Needs a terrain source |
| Route color, width, glow, casing, alternates | Yes | Yes |
| Camera mode, pitch, distance | Yes | Yes |
| Accent, panels, typography, maneuver panel | Yes | Yes |
| Label visibility | Satellite only | Yes |
| Background, land, water, park colors | **No** | Yes |
| Road colors and widths, building colors | **No** | Yes |
| Label density, size, colors | **No** | Yes |
| Traffic colors, night palette | **No** | Yes |

The Studio editor reads this matrix (`RendererCapabilities.swift`) and marks unsupported controls instead of pretending they applied. Every built-in theme still looks distinct on Apple Maps through base map, appearance, emphasis, POI, route styling, camera and UI.

## Enabling the vector engine

1. In `project.yml`, uncomment the `MapLibre` package and the `- package: MapLibre` dependency.
2. Get a tile source that serves the **OpenMapTiles** schema, for example a MapTiler key restricted to your bundle ID. These client keys are designed to be embedded; never embed a server secret.
3. Put the URLs in `Config/Secrets.xcconfig` (see `Config/Secrets.example.xcconfig`) or as GitHub secrets that the workflow writes there.
4. Rebuild. Map Studio then offers the engine switch, and Diagnostics shows "Vector engine: Ready".

CarPlay always uses the Apple Maps engine.

## Built-in themes

| Family | Themes |
|---|---|
| Essential | Classic, Dark (default), Satellite, Terrain, Minimal, Night Drive, 3D |
| Automotive | Automotive, Executive*, Cockpit, Luxury* |
| Futuristic | Neon, Cyber*, Synthwave*, Performance |

\* Premium. The brief asked for a "BMW Inspired" theme. It ships as **Oxyde Executive** so the app doesn't use another company's trademark. The look (deep blue-black, ice-blue route, restrained labels) is unchanged.
