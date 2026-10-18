# Privacy

## Defaults

- **Trip history: off.** When it's turned on, trips are stored only on the iPhone (SwiftData). Trips under 200 m are not saved.
  - "Approximate" precision (the default once enabled) keeps start and end rounded to about 100 m and no route shape.
  - "Precise" keeps the driven shape.
- **iCloud settings sync: off.** When on, only settings and saved profiles sync, through the user's own iCloud key-value store. Trips and places never leave the device.
- **Explorer mode: off.** When on, explored map squares (about 550 m) are saved only on the iPhone. Garage has an erase button.
- **XP and achievements: on, local only.** Distance, arrivals and badges are counted on the iPhone and never uploaded. They can be turned off or reset in Garage. Nothing rewards speed.
- **Convoy: only while joined.** Position is shared with that convoy's members until the driver leaves.
- **Location:** "While Using" is enough. Background location is used only during active navigation, with the blue indicator shown. Precise accuracy is requested only for navigation, via a temporary request.

## What leaves the device

| Data | Sent to | When |
|---|---|---|
| Search text, map area, route endpoints | Apple (MapKit) | Searching and routing |
| Visible map area (bounding box) | Oxyde backend | Fetching incidents, if configured |
| Report category, position, heading, optional note | Oxyde backend | Only when the user sends a report |
| Random install ID | Oxyde backend | With backend requests, for rate limits and one vote per report. It isn't linked to the Apple ID, name or device identifiers. |
| Purchases | Apple (StoreKit) | Buying or restoring |
| Position, heading, convoy display name | Oxyde backend, then the convoy's members | Only while in a convoy |
| Map area being viewed (tile requests) | OpenFreeMap | Showing the vector map |

The backend never returns who submitted a report.

## User controls

- **Settings > Privacy and Data** has the trip recording switch, the iCloud sync switch (turning it off also erases the iCloud copy), and **Erase Trips, Places and History**. Erasing removes trips, saved places, saved routes and recent destinations.
- The **Trips** screen has the precision choice.
- Custom themes are deleted from Map Studio. Deleting the app removes everything.

## App Store privacy label

Suggested answers, to be reviewed before submission:

- **Location: Precise location.** Used for App Functionality. Not linked to identity. Not used for tracking. This covers report positions and backend map-area requests.
- **User Content: Other User Content** (report notes). Used for App Functionality. Not linked to identity.
- **Identifiers: Device ID.** Covers the random install ID. Used for App Functionality (fraud prevention and rate limits). Not linked to identity.
- **Purchases.** Handled by Apple.
- No tracking, no third-party analytics and no advertising SDKs.

A privacy policy URL is required for the App Store. Write it from this page.
