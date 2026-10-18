import { randomInt, randomUUID } from 'node:crypto';
import { iso } from './rules.js';

const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const CODE_RE = /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$/;
const COLOR_RE = /^#[0-9A-Fa-f]{6}$/;
export const MAX_MEMBERS = 12;
/** A convoy ends this long after its last activity. */
export const IDLE_TTL_MS = 6 * 3600 * 1000;
/** Positions older than this are dropped, not just hidden. */
export const POSITION_TTL_MS = 5 * 60 * 1000;
/** Fastest position update a member may send. */
export const MIN_UPDATE_MS = 2000;

const cleanName = (s, fallback) => {
  if (typeof s !== 'string') return fallback;
  const t = s.replace(/[\u0000-\u001f<>]/g, '').trim().slice(0, 24);
  return t || fallback;
};

/**
 * Convoys live only in memory and are never written to disk: positions are shared with
 * the other members of one convoy and expire within minutes.
 */
export class ConvoyStore {
  constructor({ now = () => Date.now() } = {}) {
    this.now = now;
    this.convoys = new Map();
  }

  prune() {
    const t = this.now();
    for (const [code, c] of this.convoys) {
      if (t - c.lastActivity > IDLE_TTL_MS || c.members.size === 0) { this.convoys.delete(code); continue; }
      for (const m of c.members.values()) {
        if (m.position && t - m.position.at > POSITION_TTL_MS) m.position = null;
      }
    }
  }

  newCode() {
    for (;;) {
      let code = '';
      for (let i = 0; i < 6; i++) code += ALPHABET[randomInt(ALPHABET.length)];
      if (!this.convoys.has(code)) return code;
    }
  }

  create({ name, displayName, color }, install) {
    this.prune();
    if (this.convoys.size > 50_000) return { status: 503, error: 'Too many convoys' };
    const code = this.newCode();
    const convoy = { code, name: cleanName(name, 'Convoy'), members: new Map(), destination: null, lastActivity: this.now() };
    this.convoys.set(code, convoy);
    return this.addMember(convoy, { displayName, color }, install);
  }

  join(code, member, install) {
    this.prune();
    const c = this.convoys.get(code);
    if (!c) return { status: 404, error: 'Convoy not found or ended' };
    return this.addMember(c, member, install);
  }

  addMember(c, { displayName, color }, install) {
    let m = c.members.get(install);
    if (!m) {
      if (c.members.size >= MAX_MEMBERS) return { status: 409, error: 'This convoy is full' };
      m = { id: randomUUID().slice(0, 8), position: null, lastUpdate: 0 };
      c.members.set(install, m);
    }
    m.name = cleanName(displayName, 'Driver');
    m.color = COLOR_RE.test(color || '') ? color.toUpperCase() : '#7C4DFF';
    c.lastActivity = this.now();
    return { convoy: c };
  }

  update(code, { lat, lon, heading }, install) {
    this.prune();
    const c = this.convoys.get(code);
    const m = c?.members.get(install);
    if (!m) return { status: 404, error: 'Join the convoy first' };
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
      return { status: 422, error: 'lat and lon are required' };
    }
    const t = this.now();
    if (t - m.lastUpdate >= MIN_UPDATE_MS) {
      m.position = { lat, lon, heading: Number.isFinite(heading) && heading >= 0 && heading < 360 ? heading : null, at: t };
      m.lastUpdate = t;
    }
    c.lastActivity = t;
    return { convoy: c };
  }

  setDestination(code, { lat, lon, name }, install) {
    const c = this.convoys.get(code);
    if (!c?.members.has(install)) return { status: 404, error: 'Join the convoy first' };
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return { status: 422, error: 'lat and lon are required' };
    c.destination = { lat, lon, name: cleanName(name, 'Destination') };
    c.lastActivity = this.now();
    return { convoy: c };
  }

  get(code, install) {
    this.prune();
    const c = this.convoys.get(code);
    if (!c?.members.has(install)) return { status: 404, error: 'Convoy not found or ended' };
    return { convoy: c };
  }

  leave(code, install) {
    const c = this.convoys.get(code);
    if (!c?.members.delete(install)) return false;
    if (c.members.size === 0) this.convoys.delete(code);
    return true;
  }

  /** The convoy as one member sees it. Install IDs never leave the server. */
  dto(c, install) {
    return {
      code: c.code,
      name: c.name,
      expiresAt: iso(c.lastActivity + IDLE_TTL_MS),
      destination: c.destination ? [c.destination.lon, c.destination.lat] : undefined,
      destinationName: c.destination?.name,
      members: [...c.members].map(([key, m]) => ({
        id: m.id, name: m.name, color: m.color, me: key === install,
        ...(m.position ? { lat: m.position.lat, lon: m.position.lon, heading: m.position.heading ?? undefined, updatedAt: iso(m.position.at) } : {}),
      })),
    };
  }
}
