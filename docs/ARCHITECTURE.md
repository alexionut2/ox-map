# Architecture

## Layers

```
SwiftUI views (Features/*)          CarPlay templates (CarPlay/*)
        │                                   │
        └──────────── AppModel (@Observable, @MainActor) ───────────┐
                          │                                         │
   NavigationSession  TrafficStore  ReportStore  PremiumStore  SettingsStore  ThemeStore
        │                  │             │
   NavigationEngine   IncidentService  CommunityReportService     (OxydeCore protocols)
   GuidanceScheduler       │             │
        │            OxydeBackendClient (HTTP, retries, idempotency)
   RoutingService / PlaceSearchService
        │
   MapKitRoutingService, MapKitSearchService (app target)
```

- **OxydeCore** (Swift package) holds everything that can be tested without iOS: geometry, route snapping and progress, off-route detection, guidance timing and phrasing, themes and their codec, the vector style compiler, settings and profiles, the solar day/night calculation, report rules and rate limits, trip recording, place parsing and ranking, the HTTP client and the backend client. It builds and tests on Linux and macOS.
- **OxydeMap** (app) holds the iOS-specific parts: MapKit, CoreLocation, AVSpeech, StoreKit, SwiftData, CarPlay and the UI.

## Key design points

- **One navigation session for both screens.** `NavigationSession` owns planning and guidance. The phone UI and `CarPlayController` both observe it and send it commands, so a trip started in the car shows on the phone and the reverse.
- **Provider protocols.** `RoutingService`, `PlaceSearchService`, `IncidentService` and `CommunityReportService` let a provider be swapped without touching the engine or UI. Unconfigured services return a clear "not configured" error, never placeholder data.
- **Map engine abstraction.** `MapController` is implemented by `MapKitMapController` and by `VectorMapController` (compiled only when MapLibre is linked). Theme application, route overlays, incidents, the vehicle puck and camera follow are engine-specific; everything else is shared.
- **Guidance.** `NavigationEngine` turns location fixes into `RouteProgress` and events: progress, step changes, off-route, weak or lost signal, waypoint arrival and final arrival. `GuidanceScheduler` decides when to speak, using speed-dependent distances and chaining close maneuvers ("then turn left").
- **Rerouting.** Off-route detection needs three bad fixes over four seconds, scaled by GPS accuracy, and flags wrong-way driving. Reroutes are throttled to one every 8 seconds, with backoff after failures. ETAs refresh from the provider every 2 minutes.
- **Battery.** Location runs in the background only while navigating. Browsing uses 10 m accuracy with a 10 m distance filter and lets iOS pause updates, and precise accuracy is requested temporarily for navigation.
- **Recovery.** An active trip is snapshotted, so a relaunch within 3 hours offers to resume.

## Concurrency

The app uses Swift 5 language mode with minimal strict-concurrency checking. Stores and the session are `@MainActor`, and network calls are `async`. OxydeCore types are `Sendable`.

## Tests

- `OxydeCore/Tests`: 70 tests covering the engine, guidance, themes, codec, style builder, settings, rules, trips, places and the HTTP client.
- `OxydeMapTests`: MapKit conversions, settings persistence and capability honesty.
- `OxydeMapUITests`: onboarding, theme switching and the Diagnostics screen.
- `backend/test`: 13 tests for the API, rules, idempotency, voting, expiry and the TomTom mapping.
