import { createServer } from 'node:http';
import { RateLimiter, iso, parseBBox, validateSubmission } from './rules.js';
import { reportDTO, reportIncidentDTO } from './store.js';

const JSON_LIMIT = 8 * 1024;

function send(res, status, body, headers = {}) {
  const data = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers });
  res.end(data);
}

async function readJSON(req) {
  let size = 0;
  const chunks = [];
  for await (const c of req) {
    size += c.length;
    if (size > JSON_LIMIT) throw Object.assign(new Error('Body too large'), { status: 413 });
    chunks.push(c);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8') || 'null');
  } catch {
    throw Object.assign(new Error('Invalid JSON'), { status: 400 });
  }
}

const INSTALL_RE = /^[A-Za-z0-9-]{8,64}$/;

/**
 * Builds the HTTP handler. `providers` are incident sources (e.g. TomTom); none means the
 * incidents endpoint returns community reports only and says so in `sources`.
 */
export function createApp({ store, providers = [], now = () => Date.now(), adminToken = null, limiter = new RateLimiter() }) {
  const idempotency = new Map();

  async function handle(req, res) {
    const url = new URL(req.url, 'http://localhost');
    const path = url.pathname.replace(/\/+$/, '');
    const install = req.headers['x-oxyde-install'];

    if (req.method === 'GET' && (path === '' || path === '/health')) return send(res, 200, { ok: true });

    if (path.startsWith('/v1/') && !path.startsWith('/v1/admin/') && !(typeof install === 'string' && INSTALL_RE.test(install))) {
      return send(res, 400, { error: 'X-Oxyde-Install header is required' });
    }

    if (req.method === 'GET' && path === '/v1/incidents') {
      const { bbox, error } = parseBBox(url.searchParams.get('bbox'));
      if (error) return send(res, 400, { error });
      const sources = [];
      const incidents = [];
      const failures = [];
      await Promise.all(providers.map(async (p) => {
        try {
          incidents.push(...(await p.incidents(bbox)));
          sources.push(p.name);
        } catch (e) {
          failures.push(p.name);
          console.error(`${p.name} failed:`, e.message);
        }
      }));
      // If every configured provider failed, say so instead of returning a misleadingly empty map.
      if (providers.length > 0 && failures.length === providers.length) {
        return send(res, 502, { error: 'Traffic provider unavailable' });
      }
      incidents.push(...store.inArea(bbox).map(reportIncidentDTO));
      sources.push('Oxyde drivers');
      return send(res, 200, { generatedAt: iso(now()), sources, incidents });
    }

    if (req.method === 'GET' && path === '/v1/reports') {
      const { bbox, error } = parseBBox(url.searchParams.get('bbox'));
      if (error) return send(res, 400, { error });
      return send(res, 200, { reports: store.inArea(bbox).map(reportDTO) });
    }

    if (req.method === 'POST' && path === '/v1/reports') {
      const key = req.headers['idempotency-key'];
      const cacheKey = key ? `${install}:${key}` : null;
      if (cacheKey && idempotency.has(cacheKey)) {
        const prior = idempotency.get(cacheKey);
        return send(res, prior.status, prior.body);
      }
      const body = await readJSON(req);
      const t = now();
      const { value, error } = validateSubmission(body, t);
      if (error) return send(res, 422, { error });
      const limit = limiter.check(install, t);
      if (limit.retryAfter) {
        return send(res, 429, { error: 'Too many reports' }, { 'retry-after': String(limit.retryAfter) });
      }
      limiter.record(install, t);
      const { report, merged } = store.submit(value, install);
      const out = { status: merged ? 200 : 201, body: reportDTO(report) };
      if (cacheKey) {
        idempotency.set(cacheKey, out);
        if (idempotency.size > 10_000) idempotency.delete(idempotency.keys().next().value);
      }
      return send(res, out.status, out.body);
    }

    const voteMatch = path.match(/^\/v1\/reports\/([\w-]{1,64})\/votes$/);
    if (req.method === 'POST' && voteMatch) {
      const body = await readJSON(req);
      if (!body || (body.vote !== 'confirm' && body.vote !== 'dismiss')) return send(res, 422, { error: 'vote must be confirm or dismiss' });
      const result = store.vote(voteMatch[1], body.vote, install);
      if (result.error) return send(res, result.status, { error: result.error });
      return send(res, 200, { report: result.report ? reportDTO(result.report) : undefined, removed: result.removed });
    }

    const adminMatch = path.match(/^\/v1\/admin\/reports\/([\w-]{1,64})$/);
    if (req.method === 'DELETE' && adminMatch) {
      if (!adminToken || req.headers.authorization !== `Bearer ${adminToken}`) return send(res, 401, { error: 'Unauthorized' });
      return store.remove(adminMatch[1]) ? send(res, 204) : send(res, 404, { error: 'Not found' });
    }

    return send(res, 404, { error: 'Not found' });
  }

  return createServer((req, res) => {
    handle(req, res).catch((e) => {
      if (!res.headersSent) send(res, e.status || 500, { error: e.status ? e.message : 'Internal error' });
      if (!e.status) console.error(e);
    });
  });
}
