import { iso } from './rules.js';

// TomTom Traffic Incident Details v5. The key stays on this server; the app only ever
// talks to the Oxyde backend.
const FIELDS = '{incidents{type,geometry{type,coordinates},properties{id,iconCategory,magnitudeOfDelay,events{description},startTime,endTime,from,to,delay,roadNumbers,lastReportTime}}}';

const ICON_KIND = {
  1: 'accident', 2: 'weather', 3: 'hazard', 4: 'weather', 5: 'weather', 6: 'congestion', 7: 'laneClosure',
  8: 'closure', 9: 'roadworks', 10: 'weather', 11: 'weather', 14: 'hazard',
};
const MAGNITUDE = { 0: 'unknown', 1: 'minor', 2: 'moderate', 3: 'major', 4: 'unknown' };

export function mapTomTomIncident(feature, fetchedAt) {
  const p = feature.properties || {};
  const g = feature.geometry || {};
  let coords = [];
  if (g.type === 'Point' && Array.isArray(g.coordinates)) coords = [g.coordinates];
  else if (g.type === 'LineString' && Array.isArray(g.coordinates)) coords = g.coordinates;
  if (coords.length === 0) return null;
  const [lon, lat] = coords[0];
  const kind = ICON_KIND[p.iconCategory] || 'other';
  const description = (p.events || []).map((e) => e.description).filter(Boolean).join(', ');
  const road = (p.roadNumbers || []).join(', ');
  const where = [p.from, p.to].filter(Boolean).join(' to ');
  return {
    id: `tomtom-${p.id}`,
    kind,
    severity: p.iconCategory === 8 ? 'critical' : MAGNITUDE[p.magnitudeOfDelay] || 'unknown',
    lat, lon,
    geometry: coords.length > 1 ? coords : undefined,
    title: description || 'Traffic incident',
    detail: [road, where].filter(Boolean).join(': ') || undefined,
    roadClosed: p.iconCategory === 8,
    delaySeconds: Number.isFinite(p.delay) ? p.delay : undefined,
    startTime: p.startTime ? iso(Date.parse(p.startTime)) : undefined,
    endTime: p.endTime ? iso(Date.parse(p.endTime)) : undefined,
    updatedAt: iso(p.lastReportTime ? Date.parse(p.lastReportTime) : fetchedAt),
    source: 'TomTom',
  };
}

/** Fetches incidents for a bbox with a short cache keyed on a rounded bbox. */
export class TomTomIncidents {
  constructor({ apiKey, fetchImpl = fetch, ttlMs = 60_000, now = () => Date.now(), language = 'en-GB' }) {
    this.apiKey = apiKey;
    this.fetch = fetchImpl;
    this.ttl = ttlMs;
    this.now = now;
    this.language = language;
    this.cache = new Map();
  }

  get name() { return 'TomTom'; }

  async incidents(b) {
    const r = (n) => Math.round(n * 100) / 100;
    const key = [r(b.minLon), r(b.minLat), r(b.maxLon), r(b.maxLat)].join(',');
    const hit = this.cache.get(key);
    if (hit && this.now() - hit.at < this.ttl) return hit.incidents;

    const url = new URL('https://api.tomtom.com/traffic/services/5/incidentDetails');
    url.searchParams.set('key', this.apiKey);
    url.searchParams.set('bbox', `${b.minLon},${b.minLat},${b.maxLon},${b.maxLat}`);
    url.searchParams.set('fields', FIELDS);
    url.searchParams.set('language', this.language);
    url.searchParams.set('timeValidityFilter', 'present');
    const res = await this.fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new Error(`TomTom responded ${res.status}`);
    const body = await res.json();
    const fetchedAt = this.now();
    const incidents = (body.incidents || []).map((f) => mapTomTomIncident(f, fetchedAt)).filter(Boolean);
    this.cache.set(key, { at: fetchedAt, incidents });
    if (this.cache.size > 500) this.cache.delete(this.cache.keys().next().value);
    return incidents;
  }
}
