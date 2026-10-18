import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { CATEGORIES, distanceMeters, extendedExpiry, inBBox, iso, shouldRemove } from './rules.js';

/**
 * Community reports kept in memory and saved to a JSON file. This is a reference store
 * for one instance; a production deployment would use a database with a geo index.
 */
export class ReportStore {
  constructor({ file = null, now = () => Date.now() } = {}) {
    this.file = file;
    this.now = now;
    this.reports = new Map();
    // installID -> Set of report ids the install has voted on.
    this.votes = new Map();
    this.saveTimer = null;
  }

  async load() {
    if (!this.file) return;
    try {
      const data = JSON.parse(await readFile(this.file, 'utf8'));
      for (const r of data.reports || []) this.reports.set(r.id, r);
      for (const [k, ids] of Object.entries(data.votes || {})) this.votes.set(k, new Set(ids));
    } catch (e) {
      if (e.code !== 'ENOENT') throw e;
    }
    this.prune();
  }

  scheduleSave() {
    if (!this.file || this.saveTimer) return;
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      this.flush().catch((e) => console.error('save failed', e));
    }, 500);
  }

  async flush() {
    if (!this.file) return;
    const votes = Object.fromEntries([...this.votes].map(([k, s]) => [k, [...s]]));
    const tmp = `${this.file}.tmp`;
    await mkdir(dirname(this.file), { recursive: true });
    await writeFile(tmp, JSON.stringify({ reports: [...this.reports.values()], votes }));
    await rename(tmp, this.file);
  }

  prune() {
    const now = this.now();
    for (const [id, r] of this.reports) if (r.expiresAt <= now || shouldRemove(r)) this.reports.delete(id);
  }

  /**
   * Adds a report, or confirms an active one of the same category nearby. Duplicate
   * reports from different drivers strengthen one report instead of stacking pins.
   */
  submit({ category, lat, lon, heading, note }, installID) {
    this.prune();
    const now = this.now();
    const radius = CATEGORIES[category].mergeRadius;
    for (const r of this.reports.values()) {
      if (r.category !== category || distanceMeters(r, { lat, lon }) > radius) continue;
      if (r.reporter === installID) return { report: r, merged: true };
      r.confirmations += 1;
      r.expiresAt = extendedExpiry(r, now);
      this.markVoted(installID, r.id);
      this.scheduleSave();
      return { report: r, merged: true };
    }
    const report = {
      id: randomUUID(), category, lat, lon, heading, note,
      createdAt: now, expiresAt: now + CATEGORIES[category].lifetime * 1000,
      confirmations: 0, dismissals: 0, reporter: installID,
    };
    this.reports.set(report.id, report);
    this.markVoted(installID, report.id);
    this.scheduleSave();
    return { report, merged: false };
  }

  markVoted(installID, id) {
    if (!this.votes.has(installID)) this.votes.set(installID, new Set());
    this.votes.get(installID).add(id);
  }

  /** One vote per install per report. Returns { report, removed } or { error, status }. */
  vote(id, vote, installID) {
    this.prune();
    const r = this.reports.get(id);
    if (!r) return { report: null, removed: true };
    if (this.votes.get(installID)?.has(id)) return { error: 'Already voted on this report', status: 409 };
    this.markVoted(installID, id);
    if (vote === 'confirm') {
      r.confirmations += 1;
      r.expiresAt = extendedExpiry(r, this.now());
    } else {
      r.dismissals += 1;
    }
    this.scheduleSave();
    if (shouldRemove(r)) {
      this.reports.delete(id);
      return { report: null, removed: true };
    }
    return { report: r, removed: false };
  }

  remove(id) {
    const existed = this.reports.delete(id);
    if (existed) this.scheduleSave();
    return existed;
  }

  inArea(bbox) {
    this.prune();
    return [...this.reports.values()].filter((r) => inBBox(r, bbox));
  }
}

/** Public shape of a report. The reporter's install ID is never returned. */
export function reportDTO(r) {
  return {
    id: r.id, category: r.category, lat: r.lat, lon: r.lon, heading: r.heading ?? undefined,
    createdAt: iso(r.createdAt), expiresAt: iso(r.expiresAt),
    confirmations: r.confirmations, dismissals: r.dismissals, note: r.note ?? undefined,
  };
}

/** A report as an incident. `community: true` tells the app it is unverified driver input. */
export function reportIncidentDTO(r) {
  const c = CATEGORIES[r.category];
  return {
    id: `report-${r.id}`, kind: c.incidentKind, severity: 'unknown', lat: r.lat, lon: r.lon,
    title: `${c.title} reported by drivers`, roadClosed: r.category === 'closure',
    updatedAt: iso(r.createdAt), source: 'Oxyde drivers', community: true, report: reportDTO(r),
  };
}
