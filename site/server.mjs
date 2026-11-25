// Enterm's website and the Library's community shelf, at https://enterm.enmeraapps.com.
//
// Serves the static site (public/) and a small JSON API: people share prompts and race tasks from the Enterm app,
// they are published at once after automatic checks, and anyone can like or report them. Likes and reports are
// counted per install with a random id the app makes; the server keeps only salted one-way hashes of it and of the
// IP address. A maintainer reviews, hides or removes items on /admin with a token kept on the server.
//
// Zero dependencies, Node 20+. Settings by environment:
//   PORT, HOST          where it listens (127.0.0.1:8788); nginx sends WebSocket upgrades to the relay, the rest here
//   DATA_DIR            where data.json, the salt and the admin token live ($STATE_DIRECTORY under systemd)
//   PUBLIC_DIR          the site (./public)
//   TAGS_FILE           the allowed tags (./TAGS.md, copied from library/TAGS.md)

import { createServer } from 'node:http';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync, statSync, createReadStream, chmodSync } from 'node:fs';
import { join, resolve, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROGRAMS, RACE_PROGRAMS, unsafe, parseTags } from './rules.mjs';

const here = dirname(fileURLToPath(import.meta.url));

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp',
  '.ico': 'image/x-icon', '.txt': 'text/plain; charset=utf-8', '.xml': 'application/xml; charset=utf-8',
  '.woff2': 'font/woff2', '.mp4': 'video/mp4', '.webm': 'video/webm', '.webmanifest': 'application/manifest+json',
};

const SECURITY = {
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'strict-origin-when-cross-origin',
  'x-frame-options': 'DENY',
  'permissions-policy': 'camera=(), microphone=(), geolocation=()',
};

export const LIMITS = {
  submitPerHour: 5, submitPerDay: 20, votesPerHour: 300, reportsPerHour: 30,
  reportsToHide: 3, maxItems: 5000, bodyBytes: 64 * 1024,
};

/** Checks a share. Returns { item } with the cleaned fields, or { error, field }. */
export function validate(body, tags) {
  const fail = (field, error) => ({ field, error });
  if (!body || typeof body !== 'object') return fail(null, 'The request is not a JSON object.');
  const line = (v) => typeof v === 'string' && !/[\r\n]/.test(v);
  const kind = body.kind;
  if (kind !== 'prompt' && kind !== 'race') return fail('kind', 'Kind must be prompt or race.');
  const title = typeof body.title === 'string' ? body.title.trim() : '';
  if (!line(body.title) || [...title].length < 3 || [...title].length > 60) return fail('title', 'The title must be one line of 3 to 60 characters.');
  const summary = typeof body.summary === 'string' ? body.summary.trim() : '';
  if (!line(body.summary) || [...summary].length < 10 || [...summary].length > 200) return fail('summary', 'The summary must be one line of 10 to 200 characters.');
  const text = typeof body.text === 'string' ? body.text.replace(/\r\n/g, '\n').trim() : '';
  if ([...text].length < 80) return fail('text', 'The prompt must be at least 80 characters.');
  if ([...text].length > 8000) return fail('text', 'The prompt must be at most 8000 characters.');
  const programs = Array.isArray(body.programs) ? [...new Set(body.programs)] : [];
  if (programs.length === 0 || programs.some((p) => !PROGRAMS.includes(p))) return fail('programs', `Choose programs from: ${PROGRAMS.join(', ')}.`);
  const tagList = Array.isArray(body.tags) ? [...new Set(body.tags)] : [];
  if (tagList.length > 4 || tagList.some((t) => !tags.includes(t))) return fail('tags', 'Use at most 4 tags from the list.');
  let test = null;
  if (kind === 'race') {
    test = typeof body.test === 'string' ? body.test.trim() : '';
    if (!line(body.test) || test.length === 0 || test.length > 200) return fail('test', 'A race task needs a one-line test command of at most 200 characters.');
    if (programs.filter((p) => RACE_PROGRAMS.includes(p)).length < 2) return fail('programs', `A race task needs at least two of: ${RACE_PROGRAMS.join(', ')}.`);
  }
  const author = typeof body.author === 'string' ? body.author.trim() : '';
  if (author.length > 40 || (author && !/^[\p{L}\p{N} ._-]+$/u.test(author))) return fail('author', 'The name may have letters, digits, spaces, dots, dashes and underscores, 40 at most.');
  const lang = body.lang === 'tr' ? 'tr' : 'en';
  for (const [field, value] of [['title', title], ['summary', summary], ['text', text], ['test', test ?? '']]) {
    const why = unsafe(value);
    if (why) return fail(field, `This ${field === 'text' ? 'prompt' : field} ${why}. Remove it and try again.`);
  }
  return { item: { kind, title, summary, text, test, programs, tags: tagList, author: author || 'anonymous', lang } };
}

/** The store: one JSON file, written whole and renamed into place after every change. */
class Store {
  constructor(dir) {
    this.dir = dir;
    mkdirSync(dir, { recursive: true });
    this.file = join(dir, 'data.json');
    const saved = existsSync(this.file) ? JSON.parse(readFileSync(this.file, 'utf8')) : {};
    this.items = saved.items ?? [];
    this.votes = saved.votes ?? {}; // id → [device hashes]
    this.salt = this.secret('salt');
    this.adminToken = this.secret('admin-token');
  }

  secret(name) {
    const file = join(this.dir, name);
    if (!existsSync(file)) {
      writeFileSync(file, randomBytes(32).toString('hex') + '\n', { mode: 0o600 });
      chmodSync(file, 0o600);
    }
    return readFileSync(file, 'utf8').trim();
  }

  hash(value) { return createHash('sha256').update(this.salt).update('\0').update(String(value)).digest('hex').slice(0, 32); }

  save() {
    const temp = `${this.file}.${process.pid}.tmp`;
    writeFileSync(temp, JSON.stringify({ items: this.items, votes: this.votes }));
    renameSync(temp, this.file);
  }

  count(id) { return this.votes[id]?.length ?? 0; }
}

/** What anyone may see of an item; the hashes and reports stay on the server. */
function publicItem(item, store) {
  const { id, kind, title, summary, text, test, programs, tags, author, lang, created, reviewed } = item;
  return { id, kind, title, summary, text, test: test ?? undefined, programs, tags, author, lang, created, reviewed: !!reviewed, votes: store.count(id) };
}

function adminItem(item, store) {
  return { ...publicItem(item, store), hidden: !!item.hidden, hiddenReason: item.hiddenReason ?? null, reports: (item.reports ?? []).map((r) => ({ reason: r.reason, at: r.at })) };
}

/** Sliding-window counters kept in memory: a restart forgives everyone, which is fine at this size. */
class Limiter {
  constructor() { this.hits = new Map(); }
  allow(key, max, windowMs, now = Date.now()) {
    const list = (this.hits.get(key) ?? []).filter((t) => now - t < windowMs);
    if (list.length >= max) { this.hits.set(key, list); return false; }
    list.push(now);
    this.hits.set(key, list);
    if (this.hits.size > 50000) this.hits.clear();
    return true;
  }
}

const HOUR = 3600_000;
const DAY = 24 * HOUR;

export function startServer({ port = 0, host = '127.0.0.1', dataDir, publicDir = join(here, 'public'), tagsFile = join(here, 'TAGS.md'), adminFile = join(here, 'admin.html'), limits = LIMITS } = {}) {
  const store = new Store(dataDir ?? process.env.STATE_DIRECTORY ?? join(here, '.data'));
  const tags = existsSync(tagsFile) ? parseTags(readFileSync(tagsFile, 'utf8')) : [];
  const limiter = new Limiter();
  const root = resolve(publicDir);

  const send = (res, status, body, headers = {}) => {
    const json = typeof body !== 'string';
    res.writeHead(status, { ...SECURITY, 'content-type': json ? 'application/json; charset=utf-8' : 'text/plain; charset=utf-8', 'cache-control': 'no-store', ...headers });
    res.end(json ? JSON.stringify(body) : body);
  };

  const clientIP = (req) => {
    const local = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
    const forwarded = local ? (req.headers['cf-connecting-ip'] || String(req.headers['x-forwarded-for'] ?? '').split(',')[0].trim()) : '';
    return forwarded || req.socket.remoteAddress || 'unknown';
  };

  const readJSON = (req) => new Promise((done) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limits.bodyBytes) { done({ tooLarge: true }); req.destroy(); return; }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try { done({ body: JSON.parse(Buffer.concat(chunks).toString('utf8') || 'null') }); } catch { done({ body: null }); }
    });
    req.on('error', () => done({ body: null }));
  });

  const deviceOf = (body) => (typeof body?.device === 'string' && body.device.length >= 16 && body.device.length <= 128 ? body.device : null);
  const isAdmin = (req) => {
    const given = Buffer.from(String(req.headers.authorization ?? '').replace(/^Bearer\s+/i, ''));
    const wanted = Buffer.from(store.adminToken);
    return given.length === wanted.length && timingSafeEqual(given, wanted);
  };

  async function api(req, res, path) {
    const ip = store.hash(`ip:${clientIP(req)}`);

    if (req.method === 'GET' && path === '/api/library/community') {
      const sort = new URL(req.url, 'http://x').searchParams.get('sort');
      const visible = store.items.filter((i) => !i.hidden).map((i) => publicItem(i, store));
      visible.sort(sort === 'new' ? (a, b) => b.created.localeCompare(a.created) : (a, b) => b.votes - a.votes || b.created.localeCompare(a.created));
      return send(res, 200, { items: visible }, { 'cache-control': 'public, max-age=15' });
    }
    if (req.method === 'GET' && path === '/api/library/votes') {
      const votes = Object.fromEntries(Object.keys(store.votes).map((id) => [id, store.count(id)]).filter(([, n]) => n > 0));
      return send(res, 200, { votes }, { 'cache-control': 'public, max-age=15' });
    }

    if (req.method === 'POST' && path.startsWith('/api/library/')) {
      const { body, tooLarge } = await readJSON(req);
      if (tooLarge) return send(res, 413, { error: 'Too large.' });
      const device = deviceOf(body);
      if (!device) return send(res, 400, { error: 'Missing install id.' });
      const who = store.hash(`device:${device}`);
      const action = path.slice('/api/library/'.length);

      if (action === 'submit') {
        if (!limiter.allow(`s:h:${ip}`, limits.submitPerHour, HOUR) || !limiter.allow(`s:h:${who}`, limits.submitPerHour, HOUR)
          || !limiter.allow(`s:d:${ip}`, limits.submitPerDay, DAY) || !limiter.allow(`s:d:${who}`, limits.submitPerDay, DAY)) {
          return send(res, 429, { error: 'You have shared a lot in a short time. Try again later.' });
        }
        if (store.items.length >= limits.maxItems) return send(res, 503, { error: 'The community shelf is full for now.' });
        const checked = validate(body, tags);
        if (checked.error) return send(res, 400, checked);
        const textHash = store.hash(`text:${checked.item.text.toLowerCase().replace(/\s+/g, ' ')}`);
        if (store.items.some((i) => i.textHash === textHash)) return send(res, 409, { error: 'This prompt is already in the Library.', field: 'text' });
        let id;
        do { id = `c-${randomBytes(4).toString('hex')}`; } while (store.items.some((i) => i.id === id));
        const item = { id, ...checked.item, created: new Date().toISOString(), reviewed: false, hidden: false, by: who, ip, textHash, reports: [] };
        if (!item.test) delete item.test;
        store.items.push(item);
        store.save();
        return send(res, 201, { item: publicItem(item, store) });
      }

      const id = typeof body.id === 'string' ? body.id : '';
      if (action === 'vote') {
        if (!/^(c-[0-9a-f]{8}|[a-z0-9]+(-[a-z0-9]+)*)$/.test(id) || id.length > 80) return send(res, 400, { error: 'Unknown item.' });
        if (id.startsWith('c-') && !store.items.some((i) => i.id === id && !i.hidden)) return send(res, 404, { error: 'Unknown item.' });
        if (!store.votes[id] && Object.keys(store.votes).length >= limits.maxItems * 2) return send(res, 503, { error: 'Try again later.' });
        if (!limiter.allow(`v:${ip}`, limits.votesPerHour, HOUR)) return send(res, 429, { error: 'Too many likes. Try again later.' });
        const list = store.votes[id] ?? [];
        const liked = body.like === undefined ? !list.includes(who) : !!body.like;
        store.votes[id] = liked ? [...new Set([...list, who])] : list.filter((h) => h !== who);
        if (store.votes[id].length === 0) delete store.votes[id];
        store.save();
        return send(res, 200, { id, liked, votes: store.count(id) });
      }

      const item = store.items.find((i) => i.id === id);
      if (!item) return send(res, 404, { error: 'Unknown item.' });

      if (action === 'report') {
        if (!limiter.allow(`r:${ip}`, limits.reportsPerHour, HOUR)) return send(res, 429, { error: 'Too many reports. Try again later.' });
        const reason = typeof body.reason === 'string' ? body.reason.trim().slice(0, 300) : '';
        item.reports ??= [];
        if (!item.reports.some((r) => r.by === who)) item.reports.push({ by: who, reason, at: new Date().toISOString() });
        if (!item.reviewed && !item.hidden && new Set(item.reports.map((r) => r.by)).size >= limits.reportsToHide) {
          item.hidden = true;
          item.hiddenReason = 'reports';
        }
        store.save();
        return send(res, 200, { ok: true });
      }
      if (action === 'delete') {
        if (item.by !== who) return send(res, 403, { error: 'Only the Mac that shared it can take it back.' });
        store.items = store.items.filter((i) => i !== item);
        delete store.votes[id];
        store.save();
        return send(res, 200, { ok: true });
      }
      return send(res, 404, { error: 'Not found.' });
    }

    if (path.startsWith('/api/admin/')) {
      if (!isAdmin(req)) return send(res, 401, { error: 'Admin token required.' });
      if (req.method === 'GET' && path === '/api/admin/items') {
        const all = [...store.items].sort((a, b) => (b.reports?.length ?? 0) - (a.reports?.length ?? 0) || b.created.localeCompare(a.created));
        return send(res, 200, { items: all.map((i) => adminItem(i, store)) });
      }
      const match = path.match(/^\/api\/admin\/items\/(c-[0-9a-f]{8})$/);
      if (req.method === 'POST' && match) {
        const item = store.items.find((i) => i.id === match[1]);
        if (!item) return send(res, 404, { error: 'Unknown item.' });
        const { body } = await readJSON(req);
        switch (body?.action) {
          case 'hide': item.hidden = true; item.hiddenReason = 'maintainer'; break;
          case 'show': item.hidden = false; item.hiddenReason = null; item.reports = []; break;
          case 'review': item.reviewed = true; item.hidden = false; item.hiddenReason = null; item.reports = []; break;
          case 'unreview': item.reviewed = false; break;
          case 'delete': store.items = store.items.filter((i) => i !== item); delete store.votes[item.id]; break;
          default: return send(res, 400, { error: 'Action must be hide, show, review, unreview or delete.' });
        }
        store.save();
        return send(res, 200, { ok: true });
      }
    }
    return send(res, 404, { error: 'Not found.' });
  }

  function file(req, res, path) {
    if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, 'Method not allowed');
    let decoded;
    try { decoded = decodeURIComponent(path); } catch { return send(res, 400, 'Bad request'); }
    if (decoded.includes('\0')) return send(res, 400, 'Bad request');
    const candidates = decoded.endsWith('/') ? [`${decoded}index.html`] : [decoded, `${decoded}.html`, `${decoded}/index.html`];
    if (decoded === '/admin') candidates.unshift(null);
    for (const candidate of candidates) {
      const target = candidate === null ? adminFile : resolve(root, `.${candidate}`);
      if (candidate !== null && !target.startsWith(root + '/') && target !== root) continue;
      let info;
      try { info = statSync(target); } catch { continue; }
      if (!info.isFile()) continue;
      const type = TYPES[extname(target).toLowerCase()] ?? 'application/octet-stream';
      const html = type.startsWith('text/html');
      res.writeHead(200, {
        ...SECURITY, 'content-type': type, 'content-length': info.size,
        'cache-control': candidate === null ? 'no-store' : html ? 'public, max-age=0, must-revalidate' : 'public, max-age=86400',
      });
      if (req.method === 'HEAD') return res.end();
      return createReadStream(target).pipe(res);
    }
    const missing = join(root, '404.html');
    if (existsSync(missing)) {
      res.writeHead(404, { ...SECURITY, 'content-type': TYPES['.html'], 'cache-control': 'no-store' });
      return req.method === 'HEAD' ? res.end() : createReadStream(missing).pipe(res);
    }
    return send(res, 404, 'Not found');
  }

  const server = createServer((req, res) => {
    const path = (req.url ?? '/').split('?')[0];
    if (path === '/health') return send(res, 200, 'ok\n');
    if (path.startsWith('/api/')) return api(req, res, path).catch(() => send(res, 500, { error: 'Something went wrong.' }));
    return file(req, res, path);
  });
  server.listen(port, host);
  server.store = store;
  return server;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = startServer({ port: Number(process.env.PORT ?? 8788), host: process.env.HOST ?? '127.0.0.1', dataDir: process.env.DATA_DIR ?? process.env.STATE_DIRECTORY, publicDir: process.env.PUBLIC_DIR, tagsFile: process.env.TAGS_FILE });
  server.on('listening', () => console.log(`Enterm web on http://${server.address().address}:${server.address().port}`));
}
