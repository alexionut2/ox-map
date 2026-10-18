// Community report rules. These mirror OxydeCore/Reports/CommunityReports.swift so the
// app and server agree on lifetimes, merging and vote outcomes.

const MIN = 60;
const HOUR = 60 * MIN;

export const CATEGORIES = {
  accident: { lifetime: 1 * HOUR, mergeRadius: 150, incidentKind: 'accident', title: 'Accident' },
  trafficJam: { lifetime: 30 * MIN, mergeRadius: 400, incidentKind: 'congestion', title: 'Traffic jam' },
  hazard: { lifetime: 1 * HOUR, mergeRadius: 150, incidentKind: 'hazard', title: 'Road hazard' },
  roadworks: { lifetime: 8 * HOUR, mergeRadius: 250, incidentKind: 'roadworks', title: 'Roadworks' },
  closure: { lifetime: 6 * HOUR, mergeRadius: 250, incidentKind: 'closure', title: 'Road closure' },
  objectOnRoad: { lifetime: 30 * MIN, mergeRadius: 150, incidentKind: 'hazard', title: 'Object on road' },
  stoppedVehicle: { lifetime: 30 * MIN, mergeRadius: 150, incidentKind: 'hazard', title: 'Stopped vehicle' },
  police: { lifetime: 1 * HOUR, mergeRadius: 150, incidentKind: 'police', title: 'Police' },
  speedCamera: { lifetime: 2 * HOUR, mergeRadius: 150, incidentKind: 'speedCamera', title: 'Speed camera' },
  other: { lifetime: 45 * MIN, mergeRadius: 150, incidentKind: 'other', title: 'Other' },
};

export const RATE = { minIntervalSeconds: 30, maxPerHour: 10 };
export const NOTE_MAX = 140;
// Area limits keep requests cheap and match TomTom's 10,000 km² bbox cap.
export const MAX_BBOX_SPAN_DEG = 1.0;

/** ISO 8601 without fractional seconds: Swift's `.iso8601` decoder rejects milliseconds. */
export function iso(ms) {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export function distanceMeters(a, b) {
  const R = 6371008.8;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function parseBBox(value) {
  if (typeof value !== 'string') return { error: 'bbox is required as minLon,minLat,maxLon,maxLat' };
  const parts = value.split(',').map(Number);
  if (parts.length !== 4 || parts.some((n) => !Number.isFinite(n))) return { error: 'bbox must be four numbers' };
  const [minLon, minLat, maxLon, maxLat] = parts;
  if (minLon < -180 || maxLon > 180 || minLat < -90 || maxLat > 90 || minLon >= maxLon || minLat >= maxLat) {
    return { error: 'bbox is out of range' };
  }
  if (maxLon - minLon > MAX_BBOX_SPAN_DEG || maxLat - minLat > MAX_BBOX_SPAN_DEG) {
    return { error: `bbox may span at most ${MAX_BBOX_SPAN_DEG} degrees` };
  }
  return { bbox: { minLon, minLat, maxLon, maxLat } };
}

export function inBBox(p, b) {
  return p.lon >= b.minLon && p.lon <= b.maxLon && p.lat >= b.minLat && p.lat <= b.maxLat;
}

/** Validates a submission body. Returns { value } or { error }. */
export function validateSubmission(body, now) {
  if (!body || typeof body !== 'object') return { error: 'Body must be a JSON object' };
  const { category, lat, lon, heading, reportedAt, note } = body;
  if (!Object.hasOwn(CATEGORIES, category)) return { error: 'Unknown category' };
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
    return { error: 'lat/lon are invalid' };
  }
  if (heading != null && (!Number.isFinite(heading) || heading < 0 || heading >= 360)) return { error: 'heading is invalid' };
  const at = Date.parse(reportedAt);
  if (!Number.isFinite(at)) return { error: 'reportedAt is required' };
  // Reports describe what the driver sees now; stale or future timestamps are rejected.
  if (at > now + 2 * MIN * 1000 || at < now - 10 * MIN * 1000) return { error: 'reportedAt is too far from now' };
  let cleanNote = null;
  if (note != null) {
    if (typeof note !== 'string') return { error: 'note must be text' };
    const verdict = moderateNote(note);
    if (verdict.error) return verdict;
    cleanNote = verdict.value;
  }
  return { value: { category, lat, lon, heading: heading ?? null, note: cleanNote } };
}

const BLOCKED_WORDS = (process.env.OXYDE_BLOCKED_WORDS || '').split(',').map((w) => w.trim().toLowerCase()).filter(Boolean);

/** Basic moderation for free text: length, links, contact details and an operator blocklist. */
export function moderateNote(note) {
  const text = note.replace(/\s+/g, ' ').trim();
  if (text.length === 0) return { value: null };
  if (text.length > NOTE_MAX) return { error: `note may be at most ${NOTE_MAX} characters` };
  if (/(https?:\/\/|www\.)/i.test(text)) return { error: 'Links are not allowed in notes' };
  if (/[\w.+-]+@[\w-]+\.[\w.]+/.test(text) || /\+?\d[\d\s-]{7,}\d/.test(text)) {
    return { error: 'Contact details are not allowed in notes' };
  }
  const lower = text.toLowerCase();
  if (BLOCKED_WORDS.some((w) => lower.includes(w))) return { error: 'This note was not accepted' };
  return { value: text };
}

/** Extends a report's life on confirmation, capped at three base lifetimes from creation. */
export function extendedExpiry(report, now) {
  const base = CATEGORIES[report.category].lifetime * 1000;
  const extended = Math.max(report.expiresAt, now + base / 2);
  return Math.min(extended, report.createdAt + base * 3);
}

export function shouldRemove(report) {
  return report.dismissals >= 2 && report.dismissals >= report.confirmations + 2;
}

/** Sliding-window limiter per install: one report per 30 s, ten per hour. */
export class RateLimiter {
  constructor({ minIntervalSeconds, maxPerHour } = RATE) {
    this.minInterval = minIntervalSeconds * 1000;
    this.maxPerHour = maxPerHour;
    this.history = new Map();
  }

  check(key, now) {
    const list = (this.history.get(key) || []).filter((t) => now - t < 3600 * 1000);
    this.history.set(key, list);
    const last = list[list.length - 1];
    if (last != null && now - last < this.minInterval) return { retryAfter: Math.ceil((this.minInterval - (now - last)) / 1000) };
    if (list.length >= this.maxPerHour) return { retryAfter: Math.ceil((list[0] + 3600 * 1000 - now) / 1000) };
    return { ok: true };
  }

  record(key, now) {
    const list = this.history.get(key) || [];
    list.push(now);
    this.history.set(key, list);
  }
}
