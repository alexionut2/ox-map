# Oxyde backend

`backend/` is a small Node.js 20+ server with no dependencies. It does two things the app can't do safely by itself:

1. **Traffic incidents.** It calls TomTom's Traffic Incident Details API with a key that only the server knows, and returns accidents, closures, roadworks and congestion for a map area.
2. **Community reports.** It stores driver reports, merges duplicates, applies votes, expires reports and rate-limits submissions.

## Run locally

```
cd backend
npm test          # 13 tests
TOMTOM_API_KEY=your_key npm start
```

On Windows PowerShell: `$env:TOMTOM_API_KEY="your_key"; npm start`.

Without `TOMTOM_API_KEY`, the incidents endpoint returns driver reports only and lists only "Oxyde drivers" in `sources`. If TomTom is configured but fails, the endpoint returns `502` instead of an empty map that would look like "no traffic".

| Variable | Purpose |
|---|---|
| `PORT` | Default 8080 |
| `TOMTOM_API_KEY` | TomTom Traffic key (<https://developer.tomtom.com>) |
| `OXYDE_DATA_FILE` | Where reports are saved, default `data/reports.json` |
| `OXYDE_ADMIN_TOKEN` | Enables `DELETE /v1/admin/reports/{id}` for moderation |
| `OXYDE_BLOCKED_WORDS` | Comma-separated words rejected in report notes |

## Deploy

Any host that runs Docker or Node works. With Render: **New > Web Service**, connect the GitHub repo, set **Root Directory** to `backend` and **Runtime** to Docker, add the environment variables, and attach a disk at `/data`. Put the service URL in the GitHub secret `OX_BACKEND_BASE_URL` (with a trailing `/`), then run the TestFlight workflow again.

This reference server keeps reports in memory and in a JSON file, which is fine for one instance. Before a public launch, move reports to a database with a geographic index (PostGIS, or Redis GEO), put it behind HTTPS (hosts like Render do this), and add monitoring.

## API

Every `/v1` request carries `X-Oxyde-Install`, a random per-install ID that is used only for rate limits and one-vote-per-report. All dates are ISO 8601 without fractional seconds. Coordinates are `lat`/`lon`, and geometries are `[[lon, lat], ...]`.

| Method and path | Description |
|---|---|
| `GET /v1/incidents?bbox=minLon,minLat,maxLon,maxLat` | `{generatedAt, sources, incidents[]}`. Provider incidents and community reports, where `community: true` marks unverified driver input. The bbox can span at most 1 degree. |
| `GET /v1/reports?bbox=…` | `{reports[]}` |
| `POST /v1/reports` | Body `{category, lat, lon, heading?, reportedAt, note?}`. Supports `Idempotency-Key`. Returns `201` with a new report, or `200` when it confirmed an existing nearby report. Returns `422` for invalid input and `429` with `Retry-After` when rate-limited. |
| `POST /v1/reports/{id}/votes` | Body `{vote: "confirm" or "dismiss"}`. Returns `{report?, removed}`, or `409` if this install already voted or is the reporter. |
| `DELETE /v1/admin/reports/{id}` | Needs `Authorization: Bearer $OXYDE_ADMIN_TOKEN`. |
| `POST /v1/convoys` | Body `{name?, displayName?, color?}`. Creates a convoy with a 6-character code and joins it. Returns the convoy. |
| `PUT /v1/convoys/{code}/members/me` | Body `{displayName?, color?}`. Joins (max 12 drivers, `409` when full). |
| `PUT /v1/convoys/{code}/members/me/position` | Body `{lat, lon, heading?}`. Stores the position (at most every 2 s) and returns everyone's latest. |
| `PUT /v1/convoys/{code}/destination` | Body `{lat, lon, name?}`. Shares a group destination. |
| `GET /v1/convoys/{code}` | Members only (`404` otherwise). |
| `DELETE /v1/convoys/{code}/members/me` | Leaves; the convoy ends when the last driver leaves. |

Convoys live only in memory and are never written to disk. Positions are dropped after 5 minutes without an update, convoys end 6 hours after their last activity, and install IDs are never returned to other members.

## Rules

These are the same as `OxydeCore/Reports/CommunityReports.swift`:

- **Lifetimes:** jam, object and stopped vehicle 30 min; other 45 min; accident, hazard and police 1 h; speed camera 2 h; closure 6 h; roadworks 8 h. A confirmation extends a report by half its lifetime, capped at 3 lifetimes from creation.
- **Merging:** same category within 400 m for jams, 250 m for closures and roadworks, and 150 m for everything else.
- **Removal:** a report is removed after at least 2 dismissals that exceed its confirmations by 2.
- **Rate limits:** 1 report per 30 s and 10 per hour per install.
- **Validation:** `reportedAt` must be within the last 10 minutes. Notes are at most 140 characters, with no links, emails or phone numbers.
- **Region restrictions:** the app hides police and speed-camera reporting where those are restricted. If you need this enforced on the server too, add a country lookup on the coordinates before `store.submit`.
