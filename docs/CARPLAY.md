# CarPlay

## What's built

`OxydeMap/CarPlay/` implements a CarPlay **navigation** app with Apple's templates:

- `CPMapTemplate` as the root, with the Oxyde map drawn in the CarPlay window using the CarPlay theme from Settings. It follows the car's light or dark mode.
- Trip previews with route choices: fastest, time difference, distance, tolls.
- A `CPNavigationSession` with the upcoming maneuver and the one after it, live distance and time estimates, and a paused state while rerouting.
- Search with `CPSearchTemplate`, and a Places list with Home, Work, Favorites and Recent.
- A Report grid. It only appears when the backend is configured, follows the region policy, and gives a 4-second undo.
- Navigation alerts for incidents ahead and routing errors.
- Map buttons for recenter, zoom in, zoom out and pan.

Trips are shared with the phone through `NavigationSession`, so starting, rerouting or ending on either screen updates both.

## The entitlement

Apple only lets apps show on a car's screen as navigation apps if Apple has granted the **CarPlay Navigation** entitlement (`com.apple.developer.carplay-maps`).

1. Request it at <https://developer.apple.com/contact/carplay/>. Choose **Navigation**, and describe Oxyde Map as a turn-by-turn driving navigation app with live traffic and driver reports.
2. Apple reviews the request; this can take weeks, and approval isn't guaranteed.
3. Once granted, open your App ID at <https://developer.apple.com/account/resources/identifiers/list>. The CarPlay capability is enabled there; regenerate the provisioning profile if asked.
4. Add the GitHub secret `OX_ENTITLEMENTS` with the value `OxydeMap/Resources/OxydeMap-Full.entitlements`, and run the TestFlight workflow again.

Until then, device builds use `OxydeMap.entitlements` (no CarPlay), so signing never fails because of a missing entitlement. Simulator builds always use the full file, so CarPlay can be tested in the CarPlay Simulator on a Mac (Xcode > Open Developer Tool > Simulator, then I/O > External Displays > CarPlay).

The full entitlements file also enables iCloud settings sync. To use sync before CarPlay is granted, add the iCloud capability (Key-value storage) to your App ID and create your own entitlements file with only that key.

## Rules the CarPlay code follows

- Only Apple templates are used on the car display, plus the map in the base view, as the CarPlay App Programming Guide requires for navigation apps.
- No keyboard text entry while moving. `CPSearchTemplate` handles that limit itself.
- Lists are capped at `CPListTemplate.maximumItemCount`.
- No video, no dense text, no promotional content on the car screen.

## Not built yet

- CarPlay Dashboard and instrument cluster scenes. These need extra scene roles and are listed as Planned in Diagnostics.
