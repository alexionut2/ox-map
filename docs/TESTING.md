# Testing

## Automated

| Suite | Where it runs | Command |
|---|---|---|
| OxydeCore (70 tests) | Linux or macOS, and GitHub CI | `cd OxydeCore && swift test` |
| Backend (13 tests) | Node 20+ anywhere | `cd backend && npm test` |
| App tests and UI tests | macOS simulator (GitHub CI `ios` job) | `xcodebuild test -scheme OxydeMap -destination 'platform=iOS Simulator,name=iPhone 16'` |

## Manual test plan (TestFlight on iPhone)

Go through these on a real device. Things marked 🚗 need a passenger or a safe test drive. Never test while you are the one driving.

### First launch
1. Install from TestFlight and open it. Onboarding shows 4 pages. "Not Now" on location still reaches the map.
2. Settings > Diagnostics: location shows "Not asked yet" or "Off". Turn location on from there or from iOS Settings.

### Map and Studio
3. Tap the Studio button. Tap each of the 15 themes; the preview changes. Apply **Satellite**, then **Night Drive**. The map changes for real (imagery, dark style), not a tint.
4. Premium themes show a lock. In a TestFlight build, buying uses the sandbox; check that the lock goes away.
5. Long-press a theme, choose **Duplicate and Edit**, and change the route color. Controls Apple Maps can't apply are marked as needing the vector engine. Save, and share the theme to Files. Open the `.oxydetheme` file from Files, and Oxyde Map offers to import it.

### Search
6. Search an address, a business name, and coordinates such as `48.8584, 2.2945`. Results are real Apple Maps places.
7. Tap the **Fuel** and **EV** categories. Results appear near you.
8. Set Home from a place card, and check it in Places.

### Routes 🚗
9. Get directions somewhere about 10 km away. Up to 3 routes appear, with time differences. Toggle **Avoid tolls**, and the routes recalculate. **Avoid ferries** is disabled with a note.
10. Add a stop, and reorder it.
11. Start. The maneuver panel, distance, ETA and spoken instructions work. Lock the phone, and voice continues.
12. Take a wrong turn. "Rerouting" appears within a few seconds and a new route follows.
13. Drive into a tunnel or garage. A "GPS signal weak" or "lost" banner appears, and guidance resumes after.
14. Arrive. The arrival card appears, and the trip is saved only if trip history is on.

### Traffic and reports (needs the backend)
15. Diagnostics shows the backend host and "Incidents: N from TomTom, Oxyde drivers".
16. Send a report as a passenger. A 4-second undo appears, and the report shows on the map as "Reported by drivers" with an unconfirmed label.
17. Send a second report within 30 seconds. A rate-limit message names the wait.
18. On a second phone, confirm the report. Its confidence rises.

### CarPlay (Simulator on a Mac, or a car once the entitlement is granted)
19. Connect. The map shows with the CarPlay theme. Search "coffee", pick a result, preview routes, and press Go.
20. The phone shows the same trip. End on the phone, and CarPlay ends too.

### Privacy
21. Settings > Privacy and Data > Erase Trips, Places and History. Trips, recents and saved places are gone.

## What to send back if something fails

Note the step number, what you saw, and a screenshot. In TestFlight, take a screenshot and share it. TestFlight sends it to App Store Connect with device details.
