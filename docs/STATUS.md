# Status: completed vs outstanding

Last updated 2026-10-18. The in-app **Settings > Diagnostics** screen shows the same list, computed from the build's real configuration.

## How this was verified

| Check | Result |
|---|---|
| OxydeCore unit tests (engine, guidance, themes, rules, networking, explorer, XP, convoy) | **78 passed**, run on Linux with Swift 5.10 |
| Backend tests (reports, incidents, convoy) | **15 passed**, Node 22 |
| Xcode project generation from `project.yml` | Succeeds |
| Swift syntax parse of every app file | Succeeds |
| **iOS compile, app tests, UI tests** | **Not run yet.** No Mac was available. The first GitHub CI run is the first real iOS compile, and some compile fixes should be expected. |
| On-device and in-car behavior | Not tested. Use docs/TESTING.md. |

## Phases

| Phase | Scope | State |
|---|---|---|
| 1 | Architecture, providers, settings, profiles, themes model | Done |
| 2 | Map, search, places, saved places | Done |
| 3 | Routing, guidance, rerouting, voice, multi-stop | Done |
| 4 | Traffic incidents, community reports, backend | Done (backend needs deploying) |
| 5 | Map Studio, theme editor, export and import, CarPlay, Siri reporting | Done (CarPlay needs Apple's entitlement) |
| 6 | Premium, trips, diagnostics, privacy, tests, docs, cloud build | Done |
| 7 | 34 map styles on MapLibre + OpenFreeMap, oxyde.ro look, Garage (XP, badges, vehicles), Explorer mode, Convoy, animations | Done; first compile with MapLibre pending on CI |

## Feature list

✅ Working with no setup · ⚙️ Code done, needs an account, key or entitlement · ⛔ Not provided by Apple Maps · 🗓 Planned

| Area | Feature | State |
|---|---|---|
| Map | Apple Maps 2D/3D, satellite, hybrid, traffic layer | ✅ |
| Map Studio | 15 themes, live switching, day/night auto switch, CarPlay theme | ✅ |
| Map Studio | Theme editor, duplicate, export/import `.oxydetheme`, share links | ✅ |
| Map Studio | Custom land, water, road, label and building colors | ⚙️ Vector engine: MapLibre and a tile key |
| Search | Address, place, category, coordinates, autocomplete, recents | ✅ |
| Search | Along-route search, EV chargers, fuel | ✅ |
| Search | Opening hours, ratings, EV connector filters | ⛔ |
| Navigation | Routes, up to 3 alternatives, multi-stop, avoid tolls and highways | ✅ |
| Navigation | Turn-by-turn, voice, rerouting, ETA refresh, weak-GPS handling, recovery | ✅ |
| Navigation | Avoid ferries, lane guidance, speed limits | ⛔ (UI and model ready) |
| Traffic | Traffic-aware ETAs and traffic layer | ✅ |
| Traffic | Accidents, closures and roadworks feed, incident alerts ahead | ⚙️ Backend and TomTom key |
| Community | Report, undo, confirm, dismiss, expiry, rate limits, region rules | ⚙️ Backend |
| Community | Siri / Shortcuts: "Report traffic in Oxyde Map" | ⚙️ Backend |
| CarPlay | Map, previews, guidance, search, places, reports, alerts | ⚙️ Apple entitlement (Simulator works now) |
| CarPlay | Dashboard and instrument cluster | 🗓 |
| Personalization | Settings, 5 driver profiles, custom profiles, accent, HUD, voice | ✅ |
| Personalization | iCloud settings sync | ⚙️ iCloud capability |
| Trips | Opt-in history, dashboard, precision choice | ✅ |
| Premium | StoreKit 2 purchase, restore, premium themes; safety features free | ⚙️ Products in App Store Connect |
| Offline | Downloaded offline maps | ⛔ MapKit has no download API |
| Diagnostics | Permissions, services, provider capabilities, feature states | ✅ |

## Outstanding work

1. **First iOS compile on GitHub CI** and fixing what it finds.
2. **Device testing** with docs/TESTING.md, including a drive as a passenger.
3. **Deploy the backend** with a TomTom key, and set `OX_BACKEND_BASE_URL`.
4. **Request the CarPlay entitlement** (docs/CARPLAY.md).
5. **Legal review** of the police and speed-camera region list (`ReportRegionPolicy.conservativeDefault`) for each launch country.
6. **Localization.** The UI is in English only. Turn instructions come from Apple in the device language, but the surrounding phrases ("In 500 meters", "then") and the distance wording are English until translations are added to `Localizable.xcstrings`.
7. **Production backend:** a database with a geographic index, monitoring, and abuse handling at scale.
8. **App Store assets:** screenshots, privacy policy, and a review note (docs/APP_STORE.md).
9. Planned: CarPlay Dashboard and cluster, and a lane and speed-limit provider if one is licensed.
