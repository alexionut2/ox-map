import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { ReportStore } from '../src/store.js';
import { RateLimiter, iso, moderateNote, parseBBox } from '../src/rules.js';
import { TomTomIncidents, mapTomTomIncident } from '../src/tomtom.js';

const INSTALL = '11111111-2222-3333-4444-555555555555';
const OTHER = '99999999-2222-3333-4444-555555555555';
const BBOX = '2.30,48.80,2.40,48.90';

async function withServer(options, fn) {
  let t = Date.parse('2026-10-18T12:00:00Z');
  const now = () => t;
  const store = new ReportStore({ now });
  const server = createApp({ store, now, ...options });
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, { body, install = INSTALL, headers = {} } = {}) => {
    const res = await fetch(base + path, {
      method, headers: { 'x-oxyde-install': install, 'content-type': 'application/json', ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    return { status: res.status, headers: res.headers, body: text ? JSON.parse(text) : null };
  };
  try {
    await fn({ call, advance: (s) => { t += s * 1000; }, now });
  } finally {
    server.close();
  }
}

const report = (now, extra = {}) => ({ category: 'hazard', lat: 48.85, lon: 2.35, reportedAt: iso(now()), ...extra });

test('dates have no fractional seconds (Swift .iso8601 decoding)', () => {
  assert.equal(iso(Date.parse('2026-10-18T12:00:00.123Z')), '2026-10-18T12:00:00Z');
});

test('bbox validation', () => {
  assert.ok(parseBBox(BBOX).bbox);
  assert.ok(parseBBox('1,2,3').error);
  assert.ok(parseBBox('2.4,48.8,2.3,48.9').error);
  assert.ok(parseBBox('0,0,5,5').error, 'too large');
});

test('notes reject links and contact details', () => {
  assert.equal(moderateNote('  left lane   blocked ').value, 'left lane blocked');
  assert.ok(moderateNote('see www.example.com').error);
  assert.ok(moderateNote('call +33 6 12 34 56 78').error);
  assert.ok(moderateNote('x'.repeat(141)).error);
});

test('requires an install header', async () => {
  await withServer({}, async ({ call }) => {
    const r = await call('GET', `/v1/reports?bbox=${BBOX}`, { install: '' });
    assert.equal(r.status, 400);
  });
});

test('submit, list, and incidents include the report as unverified community input', async () => {
  await withServer({}, async ({ call, now }) => {
    const s = await call('POST', '/v1/reports', { body: report(now) });
    assert.equal(s.status, 201);
    assert.equal(s.body.category, 'hazard');
    assert.equal(s.body.confirmations, 0);
    assert.equal(s.body.reporter, undefined, 'reporter id is never exposed');
    const list = await call('GET', `/v1/reports?bbox=${BBOX}`);
    assert.equal(list.body.reports.length, 1);
    const inc = await call('GET', `/v1/incidents?bbox=${BBOX}`);
    assert.deepEqual(inc.body.sources, ['Oxyde drivers']);
    assert.equal(inc.body.incidents[0].community, true);
    assert.equal(inc.body.incidents[0].report.id, s.body.id);
  });
});

test('validation rejects bad input and stale timestamps', async () => {
  await withServer({}, async ({ call, now }) => {
    assert.equal((await call('POST', '/v1/reports', { body: report(now, { category: 'ufo' }) })).status, 422);
    assert.equal((await call('POST', '/v1/reports', { body: report(now, { lat: 91 }) })).status, 422);
    assert.equal((await call('POST', '/v1/reports', { body: report(now, { reportedAt: iso(now() - 3600_000) }) })).status, 422);
  });
});

test('idempotency key returns the same report without counting twice', async () => {
  await withServer({}, async ({ call, now }) => {
    const h = { 'idempotency-key': 'abc' };
    const a = await call('POST', '/v1/reports', { body: report(now), headers: h });
    const b = await call('POST', '/v1/reports', { body: report(now), headers: h });
    assert.equal(a.body.id, b.body.id);
    // A different key inside 30 s is rate limited, proving the retry wasn't counted as new.
    const c = await call('POST', '/v1/reports', { body: report(now), headers: { 'idempotency-key': 'def' } });
    assert.equal(c.status, 429);
    assert.ok(Number(c.headers.get('retry-after')) > 0);
  });
});

test('a nearby duplicate from another driver confirms the existing report', async () => {
  await withServer({}, async ({ call, now }) => {
    const a = await call('POST', '/v1/reports', { body: report(now) });
    const b = await call('POST', '/v1/reports', { body: report(now, { lat: 48.8505 }), install: OTHER });
    assert.equal(b.status, 200);
    assert.equal(b.body.id, a.body.id);
    assert.equal(b.body.confirmations, 1);
  });
});

test('votes: one per install, two net dismissals remove the report', async () => {
  await withServer({}, async ({ call, now }) => {
    const a = await call('POST', '/v1/reports', { body: report(now) });
    const id = a.body.id;
    assert.equal((await call('POST', `/v1/reports/${id}/votes`, { body: { vote: 'dismiss' } })).status, 409, 'reporter cannot vote');
    const d1 = await call('POST', `/v1/reports/${id}/votes`, { body: { vote: 'dismiss' }, install: OTHER });
    assert.equal(d1.body.removed, false);
    assert.equal((await call('POST', `/v1/reports/${id}/votes`, { body: { vote: 'dismiss' }, install: OTHER })).status, 409);
    const d2 = await call('POST', `/v1/reports/${id}/votes`, { body: { vote: 'dismiss' }, install: 'aaaaaaaa-0000' });
    assert.equal(d2.body.removed, true);
    assert.equal((await call('GET', `/v1/reports?bbox=${BBOX}`)).body.reports.length, 0);
  });
});

test('reports expire after their lifetime', async () => {
  await withServer({}, async ({ call, now, advance }) => {
    await call('POST', '/v1/reports', { body: report(now, { category: 'trafficJam' }) });
    advance(31 * 60);
    assert.equal((await call('GET', `/v1/reports?bbox=${BBOX}`)).body.reports.length, 0);
  });
});

test('rate limiter allows ten per hour', () => {
  const l = new RateLimiter();
  let t = 0;
  for (let i = 0; i < 10; i++) { assert.ok(l.check('x', t).ok); l.record('x', t); t += 31_000; }
  assert.ok(l.check('x', t).retryAfter > 0);
});

test('admin removal needs the token', async () => {
  await withServer({ adminToken: 'secret' }, async ({ call, now }) => {
    const a = await call('POST', '/v1/reports', { body: report(now) });
    assert.equal((await call('DELETE', `/v1/admin/reports/${a.body.id}`)).status, 401);
    assert.equal((await call('DELETE', `/v1/admin/reports/${a.body.id}`, { headers: { authorization: 'Bearer secret' } })).status, 204);
  });
});

test('TomTom incidents are mapped and merged; provider failure is reported, not hidden', async () => {
  const feature = {
    type: 'Feature',
    geometry: { type: 'LineString', coordinates: [[2.35, 48.85], [2.36, 48.86]] },
    properties: { id: 'abc', iconCategory: 8, magnitudeOfDelay: 4, events: [{ description: 'Closed' }], from: 'A', to: 'B',
      roadNumbers: ['A1'], delay: 120, lastReportTime: '2026-10-18T11:59:00.000Z' },
  };
  const m = mapTomTomIncident(feature, 0);
  assert.equal(m.kind, 'closure');
  assert.equal(m.roadClosed, true);
  assert.equal(m.lat, 48.85);
  assert.equal(m.updatedAt, '2026-10-18T11:59:00Z');

  let calls = 0;
  const ok = new TomTomIncidents({ apiKey: 'k', fetchImpl: async (url) => {
    calls++;
    assert.ok(String(url).includes('bbox=2.3%2C48.8%2C2.4%2C48.9'));
    return { ok: true, json: async () => ({ incidents: [feature] }) };
  } });
  await withServer({ providers: [ok] }, async ({ call }) => {
    const r = await call('GET', `/v1/incidents?bbox=${BBOX}`);
    assert.deepEqual(r.body.sources.sort(), ['Oxyde drivers', 'TomTom']);
    assert.equal(r.body.incidents[0].source, 'TomTom');
    await call('GET', `/v1/incidents?bbox=${BBOX}`);
    assert.equal(calls, 1, 'cached');
  });

  const failing = { name: 'TomTom', incidents: async () => { throw new Error('down'); } };
  await withServer({ providers: [failing] }, async ({ call }) => {
    assert.equal((await call('GET', `/v1/incidents?bbox=${BBOX}`)).status, 502);
  });
});
