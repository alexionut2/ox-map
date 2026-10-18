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

## The vector engine (default)

MapLibre is linked in `project.yml`, and with no keys configured the app uses **OpenFreeMap** (`https://tiles.openfreemap.org/planet`): free, keyless OpenMapTiles-schema tiles and fonts. Its attribution ("OpenFreeMap © OpenMapTiles Data from OpenStreetMap") is shown on the map. Every custom style (Blockworld, Neon City, Executive Navy and the rest) needs this engine, because Apple Maps doesn't allow custom map colors.

The engine is chosen per theme: the vector engine for everything, except satellite and hybrid looks when no imagery source is configured, which switch to Apple Maps automatically. The user can still pick Apple Maps in Map Studio or Settings.

To use another provider (for example MapTiler for satellite imagery or terrain), put its client-side, restricted URLs in `Config/Secrets.xcconfig` (see `Config/Secrets.example.xcconfig`). Never embed a server secret. OpenFreeMap has no uptime guarantee; for a large public release, consider self-hosting or a paid provider.

CarPlay always uses the Apple Maps engine.

## Style extras

Besides colors, a palette sets the **road shape** (smooth, or blocky with square ends), a **neon road glow**, **bold** and **uppercase** labels, and **block buildings** (heights rounded up to 8 m). Older theme files without these fields still import.

## Built-in themes (34)

| Family | Themes |
|---|---|
| Essential | Signature (default, oxyde.ro colors), Classic, Dark, Satellite, Terrain, Minimal, Night Drive, 3D |
| Automotive | Automotive, Executive*, Cockpit, Luxury*, Executive Navy, Grand Tourer, Rally Stage, Track Day |
| Futuristic | Neon, Cyber*, Synthwave*, Performance, Neon City, Chrome Rain*, Terminal |
| Game Worlds | Blockworld, Pixel Quest, Open World, Tactical Ops, Retro Arcade* |
| Artistic | Fantasy Atlas, Blueprint*, Sakura, Arctic, Mars Rover, Deep Ocean |

\* Premium (cosmetic only). Requests for "BMW", "cyberpunk" and "Minecraft" styles ship under original names (Executive Navy, Neon City, Blockworld) so the app doesn't use other companies' trademarks.
