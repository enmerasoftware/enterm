---
title: "Kata: an LRU cache with expiry in JavaScript"
summary: "Race to implement a fast, dependency-free LRU cache with per-entry expiry that passes a fixed acceptance test."
kind: race
test: node --test kata/lru-cache/*.test.mjs
programs: [claude, codex, gemini]
tags: [testing, performance]
author: enmerasoftware
title_tr: "Kata: JavaScript ile süre aşımlı LRU önbellek"
summary_tr: "Sabit bir kabul testini geçen, hızlı ve bağımlılıksız, kayıt başına süre aşımı olan bir LRU önbellek yazma yarışı."
---
Implement an LRU cache with expiry as a standalone JavaScript module. This task is self-contained: it works in any git repository, an empty one included, and needs only Node.js 20 or later.

Create `kata/lru-cache/lru-cache.mjs` exporting `class LRUCache`:

- `new LRUCache({ max, ttlMs = 0, now = Date.now, onEvict })`. `max` must be a positive integer, otherwise throw a `RangeError`. `ttlMs` is the default time to live in milliseconds; `0` means entries never expire. `now` is the clock, so tests can control time. `onEvict(key, value)` is optional.
- `get(key)` returns the value or `undefined`, and marks the entry as most recently used. It does not extend the expiry.
- `set(key, value, { ttlMs } = {})` stores the value as most recently used, with a per-entry ttl that overrides the default (`0` means never expire), and restarts the expiry. Setting an existing key replaces it without growing the cache. When the cache is over `max`, first drop expired entries, then evict least recently used entries; call `onEvict` only for these capacity evictions, not for `delete`, overwrites or expiry.
- `has(key)` says whether a live entry exists, without changing recency.
- `delete(key)` returns whether something was removed; `clear()` empties the cache.
- `size` (a getter) and `keys()` (most recently used first) count only live entries.
- `get`, `set`, `has` and `delete` must be O(1) on average. No dependencies.

Create `kata/lru-cache/acceptance.test.mjs` with exactly the content below and do not change it. You may add more tests in other files in the same folder, for example `kata/lru-cache/extra.test.mjs`.

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { LRUCache } from "./lru-cache.mjs";

function clock(start = 0) {
  let t = start;
  const now = () => t;
  now.advance = (ms) => { t += ms; };
  return now;
}

test("rejects a capacity that is not a positive integer", () => {
  for (const max of [0, -1, 1.5, NaN, "3", undefined]) {
    assert.throws(() => new LRUCache({ max }), RangeError);
  }
});

test("evicts the least recently used entry", () => {
  const c = new LRUCache({ max: 2 });
  c.set("a", 1);
  c.set("b", 2);
  c.set("c", 3);
  assert.equal(c.get("a"), undefined);
  assert.equal(c.get("b"), 2);
  assert.equal(c.get("c"), 3);
  assert.equal(c.size, 2);
});

test("get refreshes recency, has does not", () => {
  const c = new LRUCache({ max: 2 });
  c.set("a", 1);
  c.set("b", 2);
  c.get("a");
  c.set("c", 3);
  assert.equal(c.has("a"), true);
  assert.equal(c.has("b"), false);
  c.has("a");
  c.set("d", 4);
  assert.equal(c.has("a"), false);
  assert.equal(c.has("c"), true);
});

test("set on an existing key updates the value and recency without growing", () => {
  const c = new LRUCache({ max: 2 });
  c.set("a", 1);
  c.set("b", 2);
  c.set("a", 10);
  c.set("c", 3);
  assert.equal(c.size, 2);
  assert.equal(c.get("a"), 10);
  assert.equal(c.get("b"), undefined);
});

test("keys() lists most recently used first", () => {
  const c = new LRUCache({ max: 3 });
  c.set("a", 1);
  c.set("b", 2);
  c.set("c", 3);
  c.get("a");
  assert.deepEqual([...c.keys()], ["a", "c", "b"]);
});

test("stores falsy values and distinguishes them from missing keys", () => {
  const c = new LRUCache({ max: 5 });
  c.set("zero", 0);
  c.set("empty", "");
  c.set("nothing", null);
  assert.equal(c.get("zero"), 0);
  assert.equal(c.get("empty"), "");
  assert.equal(c.get("nothing"), null);
  assert.equal(c.has("nothing"), true);
  assert.equal(c.has("missing"), false);
});

test("delete and clear", () => {
  const c = new LRUCache({ max: 3 });
  c.set("a", 1);
  c.set("b", 2);
  assert.equal(c.delete("a"), true);
  assert.equal(c.delete("a"), false);
  assert.equal(c.size, 1);
  c.clear();
  assert.equal(c.size, 0);
  assert.deepEqual([...c.keys()], []);
});

test("entries expire after the default ttl", () => {
  const now = clock();
  const c = new LRUCache({ max: 3, ttlMs: 100, now });
  c.set("a", 1);
  now.advance(99);
  assert.equal(c.get("a"), 1);
  now.advance(1);
  assert.equal(c.get("a"), undefined);
  assert.equal(c.has("a"), false);
  assert.equal(c.size, 0);
});

test("a per-entry ttl overrides the default, and 0 means no expiry", () => {
  const now = clock();
  const c = new LRUCache({ max: 3, ttlMs: 100, now });
  c.set("short", 1, { ttlMs: 10 });
  c.set("forever", 2, { ttlMs: 0 });
  c.set("default", 3);
  now.advance(50);
  assert.deepEqual([...c.keys()].sort(), ["default", "forever"]);
  now.advance(1000);
  assert.deepEqual([...c.keys()], ["forever"]);
  assert.equal(c.size, 1);
});

test("get does not extend the ttl, set does", () => {
  const now = clock();
  const c = new LRUCache({ max: 3, ttlMs: 100, now });
  c.set("a", 1);
  now.advance(60);
  c.get("a");
  now.advance(60);
  assert.equal(c.get("a"), undefined);
  c.set("b", 1);
  now.advance(60);
  c.set("b", 2);
  now.advance(60);
  assert.equal(c.get("b"), 2);
});

test("expired entries do not cause live ones to be evicted", () => {
  const now = clock();
  const c = new LRUCache({ max: 2, ttlMs: 0, now });
  c.set("old", 1, { ttlMs: 10 });
  c.set("live", 2);
  now.advance(20);
  c.set("new", 3);
  assert.equal(c.get("live"), 2);
  assert.equal(c.get("new"), 3);
});

test("onEvict is called for capacity evictions but not for delete or overwrite", () => {
  const evicted = [];
  const c = new LRUCache({ max: 1, onEvict: (key, value) => evicted.push([key, value]) });
  c.set("a", 1);
  c.set("a", 2);
  c.delete("a");
  c.set("b", 3);
  c.set("c", 4);
  assert.deepEqual(evicted, [["b", 3]]);
});

test("handles many operations quickly", () => {
  const c = new LRUCache({ max: 1000 });
  const start = performance.now();
  for (let i = 0; i < 200_000; i++) {
    c.set(i % 5000, i);
    c.get((i * 7) % 5000);
  }
  assert.equal(c.size, 1000);
  assert.ok(performance.now() - start < 2000, "200k set+get pairs should take well under 2 seconds");
});
```

Done means `node --test kata/lru-cache/*.test.mjs` passes. Run it, and include the output summary in your final message together with a short note on the data structure you chose and why. Then commit your work as the instructions below say.
