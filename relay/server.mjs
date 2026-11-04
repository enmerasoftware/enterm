// Enterm relay: passes encrypted bytes between a Mac and a phone, and hands notifications to APNs.
// It cannot read what it carries, keeps no log of content and stores nothing. No dependencies.
import { createServer as createHttpServer } from 'node:http';
import { createServer as createHttpsServer } from 'node:https';
import { connect as connectHttp2 } from 'node:http2';
import { createHash, createSign, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const MAX_FRAME = 1024 * 1024;
const PING_MS = 30_000;
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const ROOM = /^[0-9a-f]{32,64}$/;

/** One RFC 6455 connection. Only what Enterm uses: binary and text messages, ping, close. */
class Peer {
  constructor(socket, onMessage, onClose) {
    this.socket = socket;
    this.onMessage = onMessage;
    this.onClose = onClose;
    this.buffer = Buffer.alloc(0);
    this.alive = true;
    this.pieces = [];
    this.pieceOpcode = 0;
    socket.on('data', (chunk) => this.feed(chunk));
    socket.on('close', () => this.onClose(this));
    socket.on('error', () => socket.destroy());
  }

  feed(chunk) {
    this.buffer = this.buffer.length ? Buffer.concat([this.buffer, chunk]) : chunk;
    if (this.buffer.length > MAX_FRAME + 16) return this.close(1009);
    for (;;) {
      if (this.buffer.length < 2) return;
      const fin = (this.buffer[0] & 0x80) !== 0;
      const opcode = this.buffer[0] & 0x0f;
      const masked = (this.buffer[1] & 0x80) !== 0;
      let length = this.buffer[1] & 0x7f;
      let offset = 2;
      if (length === 126) {
        if (this.buffer.length < 4) return;
        length = this.buffer.readUInt16BE(2);
        offset = 4;
      } else if (length === 127) {
        if (this.buffer.length < 10) return;
        const big = this.buffer.readBigUInt64BE(2);
        if (big > BigInt(MAX_FRAME)) return this.close(1009);
        length = Number(big);
        offset = 10;
      }
      if (length > MAX_FRAME) return this.close(1009);
      // A client must mask. An unmasked frame is not a WebSocket client.
      if (!masked) return this.close(1002);
      if (this.buffer.length < offset + 4 + length) return;
      const mask = this.buffer.subarray(offset, offset + 4);
      const payload = Buffer.from(this.buffer.subarray(offset + 4, offset + 4 + length));
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
      this.buffer = this.buffer.subarray(offset + 4 + length);
      this.frame(fin, opcode, payload);
      if (this.socket.destroyed) return;
    }
  }

  frame(fin, opcode, payload) {
    switch (opcode) {
      case 0x0: case 0x1: case 0x2: {
        if (opcode !== 0) this.pieceOpcode = opcode;
        this.pieces.push(payload);
        if (!fin) return;
        const whole = this.pieces.length === 1 ? this.pieces[0] : Buffer.concat(this.pieces);
        this.pieces = [];
        if (whole.length > MAX_FRAME) return this.close(1009);
        this.onMessage(this, this.pieceOpcode === 1, whole);
        return;
      }
      case 0x8: return this.close(1000);
      case 0x9: return this.write(0xa, payload);
      case 0xa: this.alive = true; return;
      default: return this.close(1002);
    }
  }

  write(opcode, payload) {
    if (this.socket.destroyed) return;
    let head;
    if (payload.length < 126) {
      head = Buffer.from([0x80 | opcode, payload.length]);
    } else if (payload.length < 65536) {
      head = Buffer.alloc(4);
      head[0] = 0x80 | opcode;
      head[1] = 126;
      head.writeUInt16BE(payload.length, 2);
    } else {
      head = Buffer.alloc(10);
      head[0] = 0x80 | opcode;
      head[1] = 127;
      head.writeBigUInt64BE(BigInt(payload.length), 2);
    }
    this.socket.write(head);
    this.socket.write(payload);
  }

  sendText(value) { this.write(0x1, Buffer.from(JSON.stringify(value))); }

  close(code) {
    const payload = Buffer.alloc(2);
    payload.writeUInt16BE(code, 0);
    this.write(0x8, payload);
    this.socket.end();
    setTimeout(() => this.socket.destroy(), 1000).unref();
  }
}

/** Sends to APNs with a token the provider key signs. The key stays on this server. */
export class Apns {
  constructor({ keyPath, keyId, teamId, topic, host = 'https://api.push.apple.com', ca }) {
    this.key = keyPath ? readFileSync(keyPath, 'utf8') : null;
    this.keyId = keyId;
    this.teamId = teamId;
    this.topic = topic;
    this.host = host;
    this.ca = ca;
    this.token = null;
    this.tokenAt = 0;
  }

  get configured() { return Boolean(this.key && this.keyId && this.teamId && this.topic); }

  providerToken() {
    const now = Math.floor(Date.now() / 1000);
    // Apple accepts a token for an hour and rejects a new one more often than every 20 minutes.
    if (this.token && now - this.tokenAt < 45 * 60) return this.token;
    const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
    const body = `${encode({ alg: 'ES256', kid: this.keyId })}.${encode({ iss: this.teamId, iat: now })}`;
    const signature = createSign('sha256').update(body).sign({ key: this.key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
    this.token = `${body}.${signature}`;
    this.tokenAt = now;
    return this.token;
  }

  send(deviceToken, sealed, kind) {
    return new Promise((resolve) => {
      if (!this.configured) return resolve({ ok: false, reason: 'not-configured' });
      if (!/^[0-9a-f]{32,200}$/i.test(deviceToken)) return resolve({ ok: false, reason: 'bad-token' });
      const client = connectHttp2(this.host, this.ca ? { ca: this.ca } : {});
      const done = (result) => { client.close(); resolve(result); };
      client.on('error', () => resolve({ ok: false, reason: 'unreachable' }));
      // Apple sees this wording. The details travel sealed and only the phone can open them.
      const payload = JSON.stringify({
        aps: { alert: { title: 'Enterm', body: 'Yeni Bir Bildirim Var' }, sound: 'default', 'mutable-content': 1, category: kind === 'approval' ? 'APPROVAL' : 'EVENT' },
        enc: sealed,
      });
      const stream = client.request({
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        authorization: `bearer ${this.providerToken()}`,
        'apns-topic': this.topic,
        'apns-push-type': 'alert',
        'apns-priority': '10',
      });
      let status = 0;
      stream.on('response', (headers) => { status = headers[':status']; });
      stream.on('error', () => done({ ok: false, reason: 'unreachable' }));
      stream.resume();
      stream.on('end', () => done(status === 200 ? { ok: true } : { ok: false, reason: `status-${status}` }));
      stream.end(payload);
    });
  }
}

export function startRelay({ port = 0, host = '127.0.0.1', tls, apns = new Apns({}), maxPushPerMinute = 30 } = {}) {
  const rooms = new Map();
  const pushes = new Map();
  let joined = 0;

  const reply = (req, res) => {
    res.writeHead(req.url === '/health' ? 200 : 404, { 'content-type': 'text/plain' });
    res.end(req.url === '/health' ? 'ok\n' : '');
  };
  const server = tls ? createHttpsServer(tls, reply) : createHttpServer(reply);

  const leave = (peer) => {
    if (!peer.room) return;
    const members = rooms.get(peer.room);
    members?.delete(peer);
    if (members?.size) for (const other of members) other.sendText({ peer: false });
    else rooms.delete(peer.room);
    peer.room = null;
  };

  const control = async (peer, text) => {
    let message;
    try { message = JSON.parse(text.toString()); } catch { return peer.close(1003); }
    if (message.join) {
      if (!ROOM.test(message.join) || peer.room) return peer.close(1008);
      const members = rooms.get(message.join) ?? new Set();
      // A room holds a Mac and a phone. A newcomer replaces a dead connection of the same role.
      for (const other of members) if (other.role === message.role) other.close(4000);
      for (const other of [...members]) if (other.role === message.role) members.delete(other);
      if (members.size >= 2) return peer.close(4001);
      peer.room = message.join;
      peer.role = message.role;
      members.add(peer);
      rooms.set(message.join, members);
      joined += 1;
      peer.sendText({ joined: true, peer: members.size === 2 });
      if (members.size === 2) for (const other of members) if (other !== peer) other.sendText({ peer: true });
    } else if (message.push && peer.room) {
      const now = Date.now();
      const log = (pushes.get(peer.room) ?? []).filter((at) => now - at < 60_000);
      if (log.length >= maxPushPerMinute) return peer.sendText({ pushed: false, reason: 'rate' });
      log.push(now);
      pushes.set(peer.room, log);
      const result = await apns.send(String(message.push.token), String(message.push.sealed), String(message.push.kind));
      peer.sendText({ pushed: result.ok, reason: result.reason });
    }
  };

  server.on('upgrade', (req, socket) => {
    const key = req.headers['sec-websocket-key'];
    if (!key || req.headers.upgrade?.toLowerCase() !== 'websocket') return socket.destroy();
    const accept = createHash('sha1').update(key + GUID).digest('base64');
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    socket.setNoDelay(true);
    const peer = new Peer(socket, (from, isText, data) => {
      if (isText) return control(from, data);
      if (!from.room) return from.close(1008);
      for (const other of rooms.get(from.room) ?? []) if (other !== from) other.write(0x2, data);
    }, leave);
    all.add(peer);
    socket.on('close', () => all.delete(peer));
  });

  const all = new Set();
  const pinger = setInterval(() => {
    for (const peer of all) {
      if (!peer.alive) { peer.socket.destroy(); continue; }
      peer.alive = false;
      peer.write(0x9, randomBytes(4));
    }
    const now = Date.now();
    for (const [room, log] of pushes) if (!log.some((at) => now - at < 60_000)) pushes.delete(room);
  }, PING_MS);
  pinger.unref();

  return new Promise((resolve) => {
    server.listen(port, host, () => resolve({
      port: server.address().port,
      stats: () => ({ rooms: rooms.size, peers: all.size, joined }),
      close: () => new Promise((done) => {
        clearInterval(pinger);
        for (const peer of all) peer.socket.destroy();
        server.close(done);
      }),
    }));
  });
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const env = process.env;
  const tls = env.RELAY_TLS_CERT ? { cert: readFileSync(env.RELAY_TLS_CERT), key: readFileSync(env.RELAY_TLS_KEY) } : undefined;
  const apns = new Apns({ keyPath: env.APNS_KEY_PATH, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC, host: env.APNS_HOST });
  const relay = await startRelay({ port: Number(env.PORT ?? 8787), host: env.HOST ?? '127.0.0.1', tls, apns });
  console.log(`enterm relay on ${relay.port}, notifications ${apns.configured ? 'on' : 'off'}`);
}
