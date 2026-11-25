#!/usr/bin/env node
// Builds index.json (and the table of contents in README.md) from prompts/*.md and skills.json.
//
//   node scripts/build-index.mjs           write index.json and the README section
//   node scripts/build-index.mjs --check   change nothing; exit 1 if anything is invalid or stale
//
// Zero dependencies, Node 20+.

import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const CHECK = process.argv.includes("--check");

const PROGRAMS = ["claude", "codex", "gemini", "opencode", "copilot", "cursor"];
const RACE_PROGRAMS = ["claude", "codex", "gemini"]; // the programs Enterm can race
const KINDS = ["prompt", "race"];
const KIND_ORDER = ["prompt", "race", "skill"];
const TAGS = readTags();
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const HANDLE = /^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$/;
const REPO = /^[A-Za-z0-9-]+\/[A-Za-z0-9._-]+$/;
const TITLE_MAX = 60;
const SUMMARY_MAX = 200;
const PROMPT_FIELDS = ["title", "summary", "kind", "test", "programs", "tags", "author", "title_tr", "summary_tr"];
const SKILL_FIELDS = ["id", "title", "summary", "repo", "path", "ref", "programs", "tags", "author", "title_tr", "summary_tr"];

// Phrases a prompt in this library must never contain. They are bait for prompt injection or
// plainly destructive; a maintainer can still reject anything else by hand.
const FORBIDDEN = [
  [/ignore (all |any )?(the )?(previous|prior|above) (instructions|messages|rules)/i, "prompt-injection bait"],
  [/disregard (all |any )?(the )?(previous|prior|above|system)/i, "prompt-injection bait"],
  [/rm\s+-rf\s+(\/|~|\$HOME)(\s|$)/i, "destructive command"],
  [/(curl|wget)[^\n|]*\|\s*(ba|z)?sh/i, "pipes a download into a shell"],
  [/--dangerously-skip-permissions|--yolo\b|--dangerously-bypass/i, "turns off the agent's permission checks"],
  [/git push\s+(-f|--force)/i, "force push"],
];

const errors = [];
const fail = (where, msg) => errors.push(`${where}: ${msg}`);

// ---------- tiny YAML subset ----------
// Supports: `key: scalar`, quoted strings ("..." with \" \\ \n escapes, '...' with ''), `key: [a, b]`,
// `key:` followed by `  - item` lines, `# comments`, `null`/`~`. Nothing else, on purpose.

function parseScalar(raw, where) {
  const s = raw.trim();
  if (s === "" || s === "null" || s === "~") return null;
  if (s.startsWith('"')) {
    if (!s.endsWith('"') || s.length < 2) { fail(where, `unterminated string: ${s}`); return null; }
    try { return JSON.parse(s); } catch { fail(where, `bad double-quoted string: ${s}`); return null; }
  }
  if (s.startsWith("'")) {
    if (!s.endsWith("'") || s.length < 2) { fail(where, `unterminated string: ${s}`); return null; }
    return s.slice(1, -1).replace(/''/g, "'");
  }
  return stripComment(s);
}

function stripComment(s) {
  const i = s.search(/\s#/);
  return (i === -1 ? s : s.slice(0, i)).trim();
}

function splitFlowList(inner) {
  const out = [];
  let cur = "", quote = null;
  for (const ch of inner) {
    if (quote) { cur += ch; if (ch === quote) quote = null; continue; }
    if (ch === '"' || ch === "'") { quote = ch; cur += ch; continue; }
    if (ch === ",") { out.push(cur); cur = ""; continue; }
    cur += ch;
  }
  if (cur.trim() !== "") out.push(cur);
  return out;
}

export function parseFrontMatter(text, where) {
  const src = text.replace(/^﻿/, "").replace(/\r\n/g, "\n");
  if (!src.startsWith("---\n")) { fail(where, "must start with a `---` front matter block"); return null; }
  const end = src.indexOf("\n---", 4);
  if (end === -1) { fail(where, "front matter is not closed with `---`"); return null; }
  const after = src.slice(end + 4);
  if (after !== "" && !after.startsWith("\n")) { fail(where, "the closing `---` must be on its own line"); return null; }
  const head = src.slice(4, end).split("\n");
  const data = {};
  let listKey = null;
  head.forEach((line, i) => {
    const at = `${where}:${i + 2}`;
    if (/^\s*(#.*)?$/.test(line)) return;
    const item = line.match(/^\s+-\s+(.*)$/) || line.match(/^-\s+(.*)$/);
    if (item) {
      if (!listKey) { fail(at, "list item without a key above it"); return; }
      (data[listKey] ??= []).push(parseScalar(item[1], at));
      return;
    }
    const kv = line.match(/^([A-Za-z_][A-Za-z0-9_]*):(?:\s+(.*))?$/);
    if (!kv) { fail(at, `cannot read this line: ${line}`); return; }
    const [, key, rest = ""] = kv;
    if (key in data) fail(at, `duplicate key \`${key}\``);
    listKey = null;
    const value = stripCommentUnlessQuoted(rest);
    if (value === "") { data[key] = null; listKey = key; return; } // becomes a list if `- item` lines follow
    if (value.startsWith("[")) {
      if (!value.endsWith("]")) { fail(at, `unterminated list: ${value}`); return; }
      data[key] = splitFlowList(value.slice(1, -1)).map((v) => parseScalar(v, at));
      return;
    }
    data[key] = parseScalar(value, at);
  });
  return { data, body: after.replace(/^\n+/, "").replace(/\s+$/, "") };
}

function stripCommentUnlessQuoted(s) {
  const t = s.trim();
  if (t.startsWith('"') || t.startsWith("'") || t.startsWith("[")) return t;
  return stripComment(t);
}

// ---------- validation helpers ----------

function readTags() {
  const file = join(ROOT, "TAGS.md");
  if (!existsSync(file)) { console.error("TAGS.md is missing"); process.exit(1); }
  const tags = [...readFileSync(file, "utf8").matchAll(/^\|\s*`([a-z0-9-]+)`\s*\|/gm)].map((m) => m[1]);
  if (tags.length === 0) { console.error("TAGS.md lists no tags (expected table rows like | `review` | ... |)"); process.exit(1); }
  return tags;
}

function checkText(where, field, value, { required = true, max = null, sentence = false } = {}) {
  if (value === null || value === undefined) { if (required) fail(where, `\`${field}\` is required`); return; }
  if (typeof value !== "string") { fail(where, `\`${field}\` must be a string`); return; }
  if (value.trim() !== value || value === "") fail(where, `\`${field}\` is empty or has leading or trailing spaces`);
  if (max && [...value].length > max) fail(where, `\`${field}\` is ${[...value].length} characters; at most ${max}`);
  if (/\n/.test(value)) fail(where, `\`${field}\` must be one line`);
  if (sentence) {
    if (!/[.!?]$/.test(value)) fail(where, `\`${field}\` must be one sentence ending with a full stop`);
    if (/[.!?]\s+\p{Lu}/u.test(value.slice(0, -1))) fail(where, `\`${field}\` must be a single sentence`);
  } else {
    if (/[.!?:;,]$/.test(value)) fail(where, `\`${field}\` must not end with punctuation`);
    if (!/^[\p{Lu}\p{N}`]/u.test(value)) fail(where, `\`${field}\` must start with a capital letter (sentence case)`);
    // Sentence case: words after the first are lowercase unless they look like names (all caps, camelCase, dotted).
    const words = value.split(/\s+/).slice(1).filter((w) => /^\p{Lu}\p{Ll}+$/u.test(w));
    if (words.length > 1) fail(where, `\`${field}\` looks like Title Case (${words.join(", ")}); use sentence case`);
  }
}

function checkList(where, field, value, allowed, { min = 1 } = {}) {
  if (!Array.isArray(value)) { fail(where, `\`${field}\` must be a list, e.g. [${allowed.slice(0, 2).join(", ")}]`); return; }
  if (value.length < min) fail(where, `\`${field}\` needs at least ${min} entr${min === 1 ? "y" : "ies"}`);
  const seen = new Set();
  for (const v of value) {
    if (!allowed.includes(v)) fail(where, `\`${field}\` has \`${v}\`; allowed: ${allowed.join(", ")}`);
    if (seen.has(v)) fail(where, `\`${field}\` lists \`${v}\` twice`);
    seen.add(v);
  }
}

function checkCommon(where, d) {
  checkText(where, "title", d.title, { max: TITLE_MAX });
  checkText(where, "summary", d.summary, { max: SUMMARY_MAX, sentence: true });
  checkText(where, "title_tr", d.title_tr, { required: false, max: TITLE_MAX });
  checkText(where, "summary_tr", d.summary_tr, { required: false, max: SUMMARY_MAX, sentence: true });
  if ((d.title_tr == null) !== (d.summary_tr == null)) fail(where, "give both `title_tr` and `summary_tr`, or neither");
  checkList(where, "programs", d.programs, PROGRAMS);
  checkList(where, "tags", d.tags, TAGS);
  if (Array.isArray(d.tags) && d.tags.length > 4) fail(where, "at most 4 tags");
  if (typeof d.author !== "string" || !HANDLE.test(d.author)) fail(where, "`author` must be a GitHub handle without @");
}

// ---------- prompts ----------

function readPrompts() {
  const dir = join(ROOT, "prompts");
  const items = [];
  for (const name of readdirSync(dir).sort()) {
    if (name.startsWith(".")) continue;
    const path = `prompts/${name}`;
    if (!name.endsWith(".md")) { fail(path, "only .md files belong in prompts/"); continue; }
    const id = basename(name, ".md");
    if (!SLUG.test(id)) fail(path, "file name must be a lowercase slug: letters, digits and single dashes");
    const parsed = parseFrontMatter(readFileSync(join(dir, name), "utf8"), path);
    if (!parsed) continue;
    const { data: d, body } = parsed;
    for (const k of Object.keys(d)) if (!PROMPT_FIELDS.includes(k)) fail(path, `unknown field \`${k}\`; allowed: ${PROMPT_FIELDS.join(", ")}`);
    if (!KINDS.includes(d.kind)) fail(path, `\`kind\` must be one of: ${KINDS.join(", ")}`);
    checkCommon(path, d);
    if (d.test != null) {
      if (d.kind !== "race") fail(path, "`test` is only for `kind: race`");
      if (typeof d.test !== "string" || d.test.trim() === "" || d.test.length > 200 || /\n/.test(d.test))
        fail(path, "`test` must be a one-line shell command of at most 200 characters");
    }
    if (d.kind === "race" && Array.isArray(d.programs)) {
      const bad = d.programs.filter((p) => !RACE_PROGRAMS.includes(p));
      if (bad.length) fail(path, `race tasks run only with ${RACE_PROGRAMS.join(", ")}; remove ${bad.join(", ")}`);
      if (d.programs.length < 2) fail(path, "a race task needs at least two programs");
    }
    if (body.length < 80) fail(path, "the prompt text after the front matter is missing or too short (80 characters at least)");
    if (body.length > 8000) fail(path, "the prompt text is longer than 8000 characters");
    for (const [re, why] of FORBIDDEN) if (re.test(body)) fail(path, `the prompt text contains ${why} (${body.match(re)[0]})`);
    items.push({
      id,
      kind: d.kind,
      title: d.title,
      summary: d.summary,
      title_tr: d.title_tr ?? null,
      summary_tr: d.summary_tr ?? null,
      text: body,
      test: d.test ?? null,
      programs: d.programs ?? [],
      tags: d.tags ?? [],
      author: d.author,
      path,
      skill: null,
      votes: 0,
    });
  }
  return items;
}

// ---------- skills ----------

function readSkills() {
  const file = join(ROOT, "skills.json");
  let list;
  try { list = JSON.parse(readFileSync(file, "utf8")); } catch (e) { fail("skills.json", `not valid JSON: ${e.message}`); return []; }
  if (!Array.isArray(list)) { fail("skills.json", "must be a JSON array of skill entries"); return []; }
  return list.map((d, i) => {
    const where = `skills.json[${i}]${d && d.id ? ` (${d.id})` : ""}`;
    if (!d || typeof d !== "object") { fail(where, "must be an object"); return null; }
    for (const k of Object.keys(d)) if (!SKILL_FIELDS.includes(k)) fail(where, `unknown field \`${k}\`; allowed: ${SKILL_FIELDS.join(", ")}`);
    if (typeof d.id !== "string" || !SLUG.test(d.id)) fail(where, "`id` must be a lowercase slug");
    checkCommon(where, d);
    if (typeof d.repo !== "string" || !REPO.test(d.repo)) fail(where, "`repo` must be `owner/name` on GitHub");
    if (typeof d.path !== "string" || d.path === "" || d.path.startsWith("/") || d.path.includes("..") || d.path.endsWith("/"))
      fail(where, "`path` must be a folder inside the repo, relative, without `..` or a trailing slash (use `.` for the root)");
    if (typeof d.ref !== "string" || d.ref === "" || /\s/.test(d.ref)) fail(where, "`ref` must be a branch, tag or commit");
    return {
      id: d.id,
      kind: "skill",
      title: d.title,
      summary: d.summary,
      title_tr: d.title_tr ?? null,
      summary_tr: d.summary_tr ?? null,
      text: null,
      test: null,
      programs: d.programs ?? [],
      tags: d.tags ?? [],
      author: d.author,
      path: null,
      skill: { repo: d.repo, path: d.path, ref: d.ref },
      votes: 0,
    };
  }).filter(Boolean);
}

// ---------- build ----------

const items = [...readPrompts(), ...readSkills()];
const ids = new Map();
for (const it of items) {
  if (ids.has(it.id)) fail(it.path ?? `skills.json (${it.id})`, `id \`${it.id}\` is already used by ${ids.get(it.id)}`);
  else ids.set(it.id, it.path ?? "skills.json");
}
items.sort((a, b) => KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind) || a.title.localeCompare(b.title, "en") || a.id.localeCompare(b.id));

const indexPath = join(ROOT, "index.json");
const old = existsSync(indexPath) ? safeJSON(readFileSync(indexPath, "utf8")) : null;
const sameItems = old && JSON.stringify(old.items) === JSON.stringify(items) && old.version === 1;
// Keep the old timestamp when nothing changed, so the file (and --check) is stable.
const index = { version: 1, generated: sameItems ? old.generated : new Date().toISOString(), items };
const indexText = JSON.stringify(index, null, 2) + "\n";

const readmePath = join(ROOT, "README.md");
const readme = existsSync(readmePath) ? readFileSync(readmePath, "utf8") : "";
const START = "<!-- index:start -->", END = "<!-- index:end -->";
let newReadme = readme;
if (!readme.includes(START) || !readme.includes(END) || readme.indexOf(START) > readme.indexOf(END)) {
  fail("README.md", `needs the markers ${START} and ${END}, in that order`);
} else {
  newReadme = readme.slice(0, readme.indexOf(START) + START.length) + "\n" + renderToc(items) + readme.slice(readme.indexOf(END));
}

if (errors.length) {
  console.error(`✗ ${errors.length} problem${errors.length === 1 ? "" : "s"}:\n`);
  for (const e of errors) console.error(`  ${e}`);
  console.error("\nSee CONTRIBUTING.md for the rules.");
  process.exit(1);
}

const LABEL = { prompt: ["prompt", "prompts"], race: ["race task", "race tasks"], skill: ["skill pack", "skill packs"] };
const counts = KIND_ORDER.map((k) => { const n = items.filter((i) => i.kind === k).length; return `${n} ${LABEL[k][n === 1 ? 0 : 1]}`; }).join(", ");
if (CHECK) {
  const stale = [];
  if (!old) stale.push("index.json is missing or not valid JSON");
  else if (!sameItems) stale.push("index.json does not match prompts/ and skills.json");
  if (newReadme !== readme) stale.push("the table of contents in README.md is out of date");
  if (stale.length) {
    for (const s of stale) console.error(`✗ ${s}`);
    console.error("\nRun `node scripts/build-index.mjs` and commit the result.");
    process.exit(1);
  }
  console.log(`✓ index.json and README.md are up to date (${counts}).`);
} else {
  writeFileSync(indexPath, indexText);
  if (newReadme !== readme) writeFileSync(readmePath, newReadme);
  console.log(`✓ Wrote index.json (${counts})${newReadme !== readme ? " and updated README.md" : ""}.`);
}

function safeJSON(s) { try { return JSON.parse(s); } catch { return null; } }

function renderToc(list) {
  const cell = (s) => String(s).replace(/\|/g, "\\|");
  const sections = [
    ["prompt", "Prompts"],
    ["race", "Race tasks"],
    ["skill", "Skill packs"],
  ];
  let out = "";
  for (const [kind, heading] of sections) {
    const rows = list.filter((i) => i.kind === kind);
    if (!rows.length) continue;
    out += `\n### ${heading} (${rows.length})\n\n`;
    if (kind === "skill") {
      out += "| Skill pack | What it does | Source | Tags |\n|---|---|---|---|\n";
      for (const i of rows) {
        const url = `https://github.com/${i.skill.repo}/tree/${i.skill.ref}/${i.skill.path === "." ? "" : i.skill.path}`.replace(/\/$/, "");
        out += `| **${cell(i.title)}** | ${cell(i.summary)} | [${i.skill.repo}${i.skill.path === "." ? "" : "/" + i.skill.path}](${url}) | ${i.tags.join(", ")} |\n`;
      }
    } else {
      out += `| ${kind === "race" ? "Race task" : "Prompt"} | What it does | Tags |\n|---|---|---|\n`;
      for (const i of rows) out += `| [${cell(i.title)}](${i.path}) | ${cell(i.summary)} | ${i.tags.join(", ")} |\n`;
    }
  }
  return out + "\n";
}
