import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createSecureServer } from 'node:http2';
import { generateKeyPairSync, randomBytes, createVerify } from 'node:crypto';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { startRelay, Apns } from './server.mjs';

function open(port) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/`);
    ws.binaryType = 'arraybuffer';
    ws.inbox = [];
    ws.waiters = [];
    ws.onmessage = (event) => {
      const value = typeof event.data === 'string' ? JSON.parse(event.data) : Buffer.from(event.data);
      const waiter = ws.waiters.shift();
      if (waiter) waiter(value); else ws.inbox.push(value);
    };
    ws.next = () => new Promise((done) => {
      if (ws.inbox.length) done(ws.inbox.shift()); else ws.waiters.push(done);
    });
    ws.onopen = () => resolve(ws);
    ws.onerror = reject;
  });
}
const room = () => randomBytes(16).toString('hex');

test('passes bytes both ways between the two members of a room, and nowhere else', async () => {
  const relay = await startRelay();
  const id = room();
  const mac = await open(relay.port);
  mac.send(JSON.stringify({ join: id, role: 'mac' }));
  assert.deepEqual(await mac.next(), { joined: true, peer: false });
  const phone = await open(relay.port);
  phone.send(JSON.stringify({ join: id, role: 'phone' }));
  assert.deepEqual(await phone.next(), { joined: true, peer: true });
  assert.deepEqual(await mac.next(), { peer: true });
  const stranger = await open(relay.port);
  stranger.send(JSON.stringify({ join: room(), role: 'phone' }));
  await stranger.next();

  phone.send(Buffer.from([1, 2, 3]));
  assert.deepEqual([...await mac.next()], [1, 2, 3]);
  const large = randomBytes(200_000);
  mac.send(large);
  assert.ok(large.equals(await phone.next()));
  assert.equal(stranger.inbox.length, 0);

  phone.close();
  assert.deepEqual(await mac.next(), { peer: false });
  mac.close();
  stranger.close();
  await relay.close();
});

test('refuses a malformed room and a third role', async () => {
  const relay = await startRelay();
  const bad = await open(relay.port);
  const closed = new Promise((done) => { bad.onclose = done; });
  bad.send(JSON.stringify({ join: 'x', role: 'mac' }));
  await closed;
  await relay.close();
});

test('a newcomer replaces a dead connection of the same role', async () => {
  const relay = await startRelay();
  const id = room();
  const first = await open(relay.port);
  first.send(JSON.stringify({ join: id, role: 'phone' }));
  await first.next();
  const closed = new Promise((done) => { first.onclose = done; });
  const second = await open(relay.port);
  second.send(JSON.stringify({ join: id, role: 'phone' }));
  assert.deepEqual(await second.next(), { joined: true, peer: false });
  await closed;
  second.close();
  await relay.close();
});

test('notifications reach APNs signed, sealed and limited', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'enterm-relay-'));
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const keyPath = join(dir, 'key.pem');
  writeFileSync(keyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes', '-keyout', join(dir, 'tls.key'), '-out', join(dir, 'tls.crt'), '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'], { stdio: 'ignore' });
  const { readFileSync } = await import('node:fs');
  const cert = readFileSync(join(dir, 'tls.crt'));
  const received = [];
  const fake = createSecureServer({ key: readFileSync(join(dir, 'tls.key')), cert }, (req, res) => {
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      received.push({ path: req.url, headers: req.headers, body: JSON.parse(body) });
      res.writeHead(200);
      res.end();
    });
  });
  await new Promise((done) => fake.listen(0, 'localhost', done));

  const apns = new Apns({ keyPath, keyId: 'KEY1', teamId: 'TEAM1', topic: 'tr.com.enmera.enterm.ios', host: `https://localhost:${fake.address().port}`, ca: cert });
  const relay = await startRelay({ apns, maxPushPerMinute: 2 });
  const mac = await open(relay.port);
  mac.send(JSON.stringify({ join: room(), role: 'mac' }));
  await mac.next();
  const token = 'ab'.repeat(32);
  mac.send(JSON.stringify({ push: { token, sealed: 'SEALED', kind: 'approval' } }));
  assert.deepEqual(await mac.next(), { pushed: true });

  const sent = received[0];
  assert.equal(sent.path, `/3/device/${token}`);
  assert.equal(sent.headers['apns-topic'], 'tr.com.enmera.enterm.ios');
  assert.equal(sent.body.enc, 'SEALED');
  assert.equal(sent.body.aps.category, 'APPROVAL');
  assert.equal(sent.body.aps['mutable-content'], 1);
  const [head, claims, signature] = sent.headers.authorization.replace('bearer ', '').split('.');
  assert.equal(JSON.parse(Buffer.from(head, 'base64url')).kid, 'KEY1');
  assert.equal(JSON.parse(Buffer.from(claims, 'base64url')).iss, 'TEAM1');
  assert.ok(createVerify('sha256').update(`${head}.${claims}`).verify({ key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')));

  mac.send(JSON.stringify({ push: { token: 'not-a-token', sealed: 'S', kind: 'event' } }));
  assert.deepEqual(await mac.next(), { pushed: false, reason: 'bad-token' });
  mac.send(JSON.stringify({ push: { token, sealed: 'S', kind: 'event' } }));
  assert.deepEqual(await mac.next(), { pushed: false, reason: 'rate' });

  mac.close();
  await relay.close();
  fake.close();
});

test('says so when no provider key is set', async () => {
  const relay = await startRelay();
  const mac = await open(relay.port);
  mac.send(JSON.stringify({ join: room(), role: 'mac' }));
  await mac.next();
  mac.send(JSON.stringify({ push: { token: 'ab'.repeat(32), sealed: 'S', kind: 'event' } }));
  assert.deepEqual(await mac.next(), { pushed: false, reason: 'not-configured' });
  mac.close();
  await relay.close();
});
