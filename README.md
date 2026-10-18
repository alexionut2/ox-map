# Oxyde Map

A premium iPhone and CarPlay navigation app: Apple Maps routing and live traffic, community road reports, and Map Studio, a theme system with 15 built-in looks and a custom theme editor.

**Status:** the code is complete for a first TestFlight build. It has not yet been compiled for iOS, because it was written on Linux and Windows. The GitHub workflow in `.github/workflows/ci.yml` does that compile on a cloud Mac. [docs/STATUS.md](docs/STATUS.md) lists exactly what works, what needs setup and what is outside the provider's limits.

## Start here

| You want to | Read |
|---|---|
| Build and install on your iPhone from Windows | [docs/SETUP.md](docs/SETUP.md) |
| See what is finished and what isn't | [docs/STATUS.md](docs/STATUS.md) |
| Understand the code | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Know why Apple Maps, and what each engine can theme | [docs/PROVIDERS.md](docs/PROVIDERS.md) |
| Run the traffic and reports server | [docs/BACKEND.md](docs/BACKEND.md) |
| Get CarPlay working in a real car | [docs/CARPLAY.md](docs/CARPLAY.md) |
| Test the app by hand | [docs/TESTING.md](docs/TESTING.md) |
| Ship to the App Store | [docs/APP_STORE.md](docs/APP_STORE.md) |
| Privacy details | [docs/PRIVACY.md](docs/PRIVACY.md) |

## Layout

```
OxydeCore/        Swift package: navigation engine, guidance, themes, rules. Pure Swift, tested on Linux too.
OxydeMap/         The iOS app (SwiftUI, MapKit, CarPlay, StoreKit, SwiftData).
OxydeMapTests/    App tests that need iOS frameworks.
OxydeMapUITests/  UI smoke tests.
backend/          Node.js server for traffic incidents and community reports (no dependencies).
Config/           Build settings. Put your own values in Config/Secrets.xcconfig.
project.yml       XcodeGen spec. `xcodegen generate` produces OxydeMap.xcodeproj.
.github/          Cloud builds: CI on every push, TestFlight upload on demand.
```

## Accounts and services

| What | Needed for | Cost |
|---|---|---|
| Apple Developer Program | TestFlight, App Store, device installs | $99 per year |
| GitHub account | Cloud Mac builds | Free (macOS minutes are limited on private repos) |
| CarPlay navigation entitlement | CarPlay in a real car | Free, Apple approval required |
| TomTom Traffic API key | Accidents, closures, roadworks feed (server side) | Free tier, then paid |
| Any Node host (Render, Fly.io, a VPS) | The Oxyde backend | Free tiers exist |
| MapTiler or other OpenMapTiles host | Optional vector engine with fully custom colors | Free tier, then paid |

Apple Maps search, routing, traffic and ETAs need no key.
