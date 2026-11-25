/* Enterm site: browse the Library (reviewed index + community entries). Read only.
   All item text is set with textContent, never as HTML: community entries are user-submitted. */
(function () {
  "use strict";
  var E = window.Enterm, t = E.t;
  var INDEX = "https://raw.githubusercontent.com/enmerasoftware/enterm/main/library/index.json";
  var COMMUNITY = "/api/library/community";
  var VOTES = "/api/library/votes";
  var REPO_BLOB = "https://github.com/enmerasoftware/enterm/blob/main/library/";
  var DOWNLOAD = "https://github.com/enmerasoftware/enterm/releases/latest";
  var KINDS = { prompt: ["kind_prompt", "Prompt", "k-prompt"], race: ["kind_race", "Race task", "k-race"], skill: ["kind_skill", "Skill pack", "k-skill"] };
  var PROGRAMS = { claude: "Claude Code", codex: "Codex", gemini: "Gemini", opencode: "opencode", copilot: "GitHub Copilot", cursor: "Cursor", agy: "Antigravity", grok: "Grok" };

  var $ = function (s) { return document.querySelector(s); };
  var grid = $("#grid"), state = $("#state"), line = $("#result-line"), tagsEl = $("#tags"), q = $("#q");
  var cGrid = $("#comm-grid"), cState = $("#comm-state"), cLine = $("#comm-line"), cSection = $("#community");
  var revSection = grid.closest("section");
  var dlg = $("#detail");

  var reviewed = [], community = [], votes = null;
  var revStatus = "loading", commStatus = "loading";
  var kind = "all", tag = "", query = "", source = "all", sort = "top", openId = null;

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function str(v, max) { return typeof v === "string" ? v.slice(0, max || 20000) : ""; }
  function int(v) { return typeof v === "number" && isFinite(v) && v >= 0 ? Math.floor(v) : 0; }
  function fold(s) {
    return s.replace(/ı/g, "i").replace(/İ/g, "i").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  }
  function title(it) { return E.lang() === "tr" && it.title_tr ? it.title_tr : it.title; }
  function summary(it) { return E.lang() === "tr" && it.summary_tr ? it.summary_tr : it.summary; }
  function likes(it) { return it.community ? it.votes : (votes && votes[it.id] != null ? int(votes[it.id]) : it.votes); }

  function base(raw) {
    var it = {
      kind: raw.kind,
      title: str(raw.title, 300), summary: str(raw.summary, 1000),
      title_tr: "", summary_tr: "",
      text: str(raw.text, 50000), test: str(raw.test, 500), author: str(raw.author, 100),
      programs: Array.isArray(raw.programs) ? raw.programs.filter(function (p) { return typeof p === "string" && p.length < 40; }).slice(0, 12) : [],
      tags: Array.isArray(raw.tags) ? raw.tags.filter(function (p) { return typeof p === "string" && /^[a-z0-9-]{1,40}$/.test(p); }).slice(0, 12) : [],
      votes: int(raw.votes)
    };
    return it;
  }
  function hay(it) {
    it.hay = fold([it.title, it.summary, it.title_tr, it.summary_tr, it.text, it.tags.join(" "), it.programs.join(" "),
      it.programs.map(function (p) { return PROGRAMS[p] || ""; }).join(" "), it.test, it.author].join(" \n "));
    return it;
  }

  function cleanReviewed(raw) {
    if (!raw || typeof raw !== "object" || !KINDS[raw.kind]) return null;
    var id = str(raw.id, 120);
    if (!/^[a-z0-9][a-z0-9-]*$/.test(id) || !str(raw.title)) return null;
    var it = base(raw);
    it.id = id;
    it.title_tr = str(raw.title_tr, 300);
    it.summary_tr = str(raw.summary_tr, 1000);
    var path = str(raw.path);
    it.path = /^[A-Za-z0-9_\/.-]+$/.test(path) && path.indexOf("..") < 0 ? path : "";
    var s = raw.skill;
    it.skill = null;
    if (s && typeof s === "object" && /^[A-Za-z0-9-]+\/[A-Za-z0-9._-]+$/.test(str(s.repo)) &&
        /^[A-Za-z0-9_\/.-]*$/.test(str(s.path)) && str(s.path).indexOf("..") < 0 && /^[A-Za-z0-9._\/-]+$/.test(str(s.ref) || "main")) {
      it.skill = { repo: s.repo, path: str(s.path), ref: str(s.ref) || "main" };
    }
    return hay(it);
  }

  function cleanCommunity(raw) {
    if (!raw || typeof raw !== "object" || (raw.kind !== "prompt" && raw.kind !== "race")) return null;
    var id = str(raw.id, 64);
    if (!/^c-[A-Za-z0-9_-]{4,40}$/.test(id) || !str(raw.title) || !str(raw.text)) return null;
    var it = base(raw);
    it.id = id;
    it.community = true;
    it.reviewed = raw.reviewed === true;
    it.lang = raw.lang === "tr" ? "tr" : raw.lang === "en" ? "en" : "";
    var d = new Date(str(raw.created, 40));
    it.created = isNaN(d.getTime()) ? 0 : d.getTime();
    return hay(it);
  }

  // ---------- URL state ----------
  function readURL() {
    try {
      var p = new URLSearchParams(location.search);
      query = (p.get("q") || "").slice(0, 200);
      kind = KINDS[p.get("kind")] ? p.get("kind") : "all";
      tag = /^[a-z0-9-]{1,40}$/.test(p.get("tag") || "") ? p.get("tag") : "";
      source = p.get("source") === "reviewed" || p.get("source") === "community" ? p.get("source") : "all";
      sort = p.get("sort") === "new" ? "new" : "top";
      q.value = query;
    } catch (e) {}
  }
  function writeURL() {
    try {
      var p = new URLSearchParams();
      if (query) p.set("q", query);
      if (kind !== "all") p.set("kind", kind);
      if (tag) p.set("tag", tag);
      if (source !== "all") p.set("source", source);
      if (sort !== "top") p.set("sort", sort);
      var s = p.toString();
      history.replaceState(null, "", location.pathname + (s ? "?" + s : "") + location.hash);
    } catch (e) {}
  }

  // ---------- render ----------
  function matches(it) {
    if (kind !== "all" && it.kind !== kind) return false;
    if (tag && it.tags.indexOf(tag) < 0) return false;
    var words = fold(query).split(/\s+/).filter(Boolean);
    for (var i = 0; i < words.length; i++) if (it.hay.indexOf(words[i]) < 0) return false;
    return true;
  }
  function all() { return reviewed.concat(community); }
  function find(id) { return all().filter(function (x) { return x.id === id; })[0]; }

  function pressed(sel, attr, value) {
    document.querySelectorAll(sel).forEach(function (b) { b.setAttribute("aria-pressed", b.getAttribute(attr) === value ? "true" : "false"); });
  }

  function renderCounts() {
    var pool = source === "reviewed" ? reviewed : source === "community" ? community : all();
    var c = { all: pool.length, prompt: 0, race: 0, skill: 0 };
    pool.forEach(function (it) { c[it.kind]++; });
    var any = reviewed.length || community.length;
    document.querySelectorAll(".kinds [data-n]").forEach(function (b) { b.textContent = any ? String(c[b.getAttribute("data-n")]) : ""; });
    pressed(".kinds [data-kind]", "data-kind", kind);
    pressed(".sources [data-src]", "data-src", source);
    pressed(".sort [data-sort]", "data-sort", sort);
  }

  function renderTags() {
    var count = {};
    all().forEach(function (it) { it.tags.forEach(function (g) { count[g] = (count[g] || 0) + 1; }); });
    var list = Object.keys(count).sort(function (a, b) { return count[b] - count[a] || a.localeCompare(b); });
    tagsEl.textContent = "";
    list.forEach(function (g) {
      var b = el("button", "tag", g);
      b.type = "button";
      b.setAttribute("aria-pressed", g === tag ? "true" : "false");
      b.addEventListener("click", function () { tag = tag === g ? "" : g; update(); });
      tagsEl.appendChild(b);
    });
  }

  function ago(ms) {
    if (!ms) return "";
    var diff = (ms - Date.now()) / 1000;
    var units = [["year", 31536000], ["month", 2592000], ["week", 604800], ["day", 86400], ["hour", 3600], ["minute", 60]];
    try {
      var rtf = new Intl.RelativeTimeFormat(E.lang(), { numeric: "auto" });
      for (var i = 0; i < units.length; i++) {
        if (Math.abs(diff) >= units[i][1]) return rtf.format(Math.round(diff / units[i][1]), units[i][0]);
      }
      return rtf.format(0, "minute");
    } catch (e) { return new Date(ms).toLocaleDateString(); }
  }

  function commBadge(it) {
    return it.reviewed ? el("span", "kind k-commrev", t("comm_badge_rev", "Community · reviewed"))
                       : el("span", "kind k-comm", t("comm_badge", "Community · unreviewed"));
  }

  function card(it, i) {
    var b = el("button", "item" + (it.community ? " c-item" + (it.reviewed ? " rev" : "") : ""));
    b.type = "button";
    b.style.animationDelay = Math.min(i, 12) * 30 + "ms";
    var row = el("div", "row");
    row.appendChild(el("span", "kind " + KINDS[it.kind][2], t(KINDS[it.kind][0], KINDS[it.kind][1])));
    if (it.community) row.appendChild(commBadge(it));
    if (it.test) row.appendChild(el("span", "test", "✓ " + t("lp_has_test", "test included")));
    var n = likes(it);
    if (it.community || votes || n > 0) {
      var lk = el("span", "likes", String(n));
      lk.setAttribute("aria-label", t("lp_likes_n", "{n} likes").replace("{n}", n));
      row.appendChild(lk);
    }
    b.appendChild(row);
    b.appendChild(el("h3", "", title(it)));
    if (summary(it)) b.appendChild(el("p", "", summary(it)));
    var progs = el("div", "progs");
    it.programs.forEach(function (p) { progs.appendChild(el("span", "prog", PROGRAMS[p] || p)); });
    if (it.community) {
      if (it.lang) progs.appendChild(el("span", "lang-tag", it.lang));
      var w = el("span", "when", (it.author ? it.author + " · " : "") + ago(it.created));
      progs.appendChild(w);
    }
    b.appendChild(progs);
    b.addEventListener("click", function () { open(it.id); });
    return b;
  }

  function emptyState(box, text, withReset) {
    box.textContent = "";
    box.appendChild(el("p", "", text));
    if (withReset) {
      var reset = el("button", "btn btn-small", t("lp_clear", "Clear filters"));
      reset.type = "button";
      reset.addEventListener("click", function () { query = ""; q.value = ""; kind = "all"; tag = ""; source = "all"; update(); q.focus(); });
      box.appendChild(reset);
    }
  }
  function filtersOn() { return !!(query || tag || kind !== "all"); }

  function update() {
    writeURL();
    renderCounts();
    renderTags();

    // reviewed
    revSection.hidden = source === "community";
    var list = reviewed.filter(matches);
    if (votes) list = list.slice().sort(function (a, b) { return likes(b) - likes(a); });
    grid.textContent = "";
    list.forEach(function (it, i) { grid.appendChild(card(it, i)); });
    if (revStatus === "ok") {
      line.textContent = t("lp_showing", "{n} of {total}").replace("{n}", list.length).replace("{total}", reviewed.length);
      if (list.length) state.textContent = "";
      else emptyState(state, t("lp_none", "Nothing matches. Try fewer words or another kind."), filtersOn());
    }

    // community
    cSection.hidden = source === "reviewed" || kind === "skill";
    var clist = community.filter(matches).sort(function (a, b) {
      return sort === "new" ? b.created - a.created : (b.votes - a.votes) || (b.created - a.created);
    });
    cGrid.textContent = "";
    clist.forEach(function (it, i) { cGrid.appendChild(card(it, i)); });
    if (commStatus === "ok") {
      cLine.textContent = community.length ? t("lp_showing", "{n} of {total}").replace("{n}", clist.length).replace("{total}", community.length) : "";
      if (clist.length) cState.textContent = "";
      else if (!community.length) emptyState(cState, t("lp_comm_empty", "Nothing shared yet. Be the first: in Enterm, open the Library and press Share."));
      else emptyState(cState, t("lp_none", "Nothing matches. Try fewer words or another kind."), filtersOn());
    }
  }

  // ---------- detail ----------
  function metaRow(dl, label, node) {
    dl.appendChild(el("dt", "", label));
    var dd = el("dd");
    if (typeof node === "string") dd.textContent = node; else dd.appendChild(node);
    dl.appendChild(dd);
  }
  function link(href, text, primary) {
    var a = el("a", "btn btn-small" + (primary ? " btn-primary" : ""), text);
    a.href = href;
    a.rel = "noopener";
    return a;
  }

  function fillDetail(it) {
    var k = $("#d-kind");
    k.className = "kind " + KINDS[it.kind][2];
    k.textContent = t(KINDS[it.kind][0], KINDS[it.kind][1]);
    var old = k.parentNode.querySelector(".d-badge");
    if (old) old.remove();
    if (it.community) {
      var badge = commBadge(it);
      badge.classList.add("d-badge");
      k.insertAdjacentElement("afterend", badge);
    }
    $("#d-title").textContent = title(it);
    $("#d-summary").textContent = summary(it);
    $("#d-warn").hidden = !(it.community && !it.reviewed);
    var dl = $("#d-meta");
    dl.textContent = "";
    if (it.programs.length) {
      var ps = document.createDocumentFragment();
      it.programs.forEach(function (p) { ps.appendChild(el("span", "prog", PROGRAMS[p] || p)); });
      metaRow(dl, t("lp_programs", "Programs"), ps);
    }
    if (it.tags.length) metaRow(dl, t("lp_tags", "Tags"), it.tags.map(function (g) { return "#" + g; }).join("  "));
    if (it.test) metaRow(dl, t("lp_test", "Test command"), el("code", "", it.test));
    if (it.author) metaRow(dl, t("lp_author", "Author"), it.author);
    if (it.community && it.lang) metaRow(dl, t("lp_lang", "Language"), it.lang === "tr" ? "Türkçe" : "English");
    if (it.community && it.created) metaRow(dl, t("lp_shared", "Shared"), new Date(it.created).toLocaleDateString(E.lang()) + " (" + ago(it.created) + ")");
    if (it.community || votes) metaRow(dl, t("lp_likes", "Likes"), String(likes(it)));

    $("#d-text-wrap").hidden = !it.text;
    $("#d-text").textContent = it.text;

    var sk = $("#d-skill");
    sk.textContent = "";
    if (it.kind === "skill") {
      sk.appendChild(el("p", "", t("lp_skill_note", "A skill pack is a folder of files. In Enterm, Review Files and Add lists every file, the ones that can run something first, and adds it only when you press Add.")));
    }
    var links = $("#d-links");
    links.textContent = "";
    links.appendChild(link(DOWNLOAD, t("lp_get_short", "Get Enterm"), true));
    if (it.path) links.appendChild(link(REPO_BLOB + it.path, t("lp_view_src", "View on GitHub")));
    if (it.skill) links.appendChild(link("https://github.com/" + it.skill.repo + "/tree/" + it.skill.ref + "/" + it.skill.path, t("lp_view_pack", "Browse the pack's files")));
  }

  function open(id, fromHash) {
    var it = find(id);
    if (!it) return false;
    if (!dlg.open) trigger = document.activeElement && document.activeElement !== document.body ? document.activeElement : null;
    openId = id;
    fillDetail(it);
    if (!fromHash) { try { history.replaceState(null, "", location.pathname + location.search + "#" + id); } catch (e) {} }
    if (typeof dlg.showModal === "function") { if (!dlg.open) dlg.showModal(); }
    else dlg.setAttribute("open", "");
    $("#d-close").focus();
    return true;
  }
  function close() {
    if (dlg.open && typeof dlg.close === "function") dlg.close();
    else { dlg.removeAttribute("open"); onClose(); }
  }
  var trigger = null;
  function onClose() {
    openId = null;
    try { history.replaceState(null, "", location.pathname + location.search); } catch (e) {}
    if (trigger && document.contains(trigger)) trigger.focus();
    trigger = null;
  }
  dlg.addEventListener("close", onClose);
  $("#d-close").addEventListener("click", close);
  dlg.addEventListener("click", function (e) { if (e.target === dlg) close(); });
  $("#d-copy").addEventListener("click", function () {
    var it = find(openId);
    if (it && it.text) E.copy(it.text, this);
  });
  function openFromHash() {
    var id = "";
    try { id = decodeURIComponent(location.hash.slice(1)); } catch (e) {}
    if (id && id !== openId) open(id, true);
  }
  window.addEventListener("hashchange", openFromHash);

  // ---------- controls ----------
  var timer;
  q.addEventListener("input", function () {
    clearTimeout(timer);
    timer = setTimeout(function () { query = q.value.slice(0, 200); update(); }, 120);
  });
  document.querySelectorAll(".kinds [data-kind]").forEach(function (b) {
    b.addEventListener("click", function () { kind = b.getAttribute("data-kind"); update(); });
  });
  document.querySelectorAll(".sources [data-src]").forEach(function (b) {
    b.addEventListener("click", function () { source = b.getAttribute("data-src"); update(); });
  });
  document.querySelectorAll(".sort [data-sort]").forEach(function (b) {
    b.addEventListener("click", function () { sort = b.getAttribute("data-sort"); update(); });
  });
  document.addEventListener("keydown", function (e) {
    var a = document.activeElement;
    if (e.key === "/" && a !== q && !dlg.open && !/INPUT|TEXTAREA|SELECT/.test((a && a.tagName) || "")) { e.preventDefault(); q.focus(); }
  });
  E.onLang(function () {
    update();
    var it = openId && find(openId);
    if (it) fillDetail(it);
  });

  // ---------- load ----------
  function getJSON(url, opts) {
    return fetch(url, opts).then(function (r) {
      if (!r.ok) throw new Error(r.status);
      var ct = r.headers.get("content-type") || "";
      if (ct.indexOf("json") < 0 && url.charAt(0) === "/") throw new Error("not json");
      return r.json();
    });
  }

  function loadReviewed() {
    revStatus = "loading";
    state.textContent = t("lp_loading", "Loading the Library…");
    return getJSON(INDEX, { cache: "no-cache" })
      .then(function (d) {
        var seen = {};
        reviewed = (d && Array.isArray(d.items) ? d.items : []).map(cleanReviewed).filter(function (it) {
          if (!it || seen[it.id]) return false; seen[it.id] = 1; return true;
        });
        if (!reviewed.length) throw new Error("empty");
        revStatus = "ok";
        update();
      })
      .catch(function () {
        revStatus = "error";
        state.textContent = "";
        state.appendChild(el("p", "", t("lp_error", "The reviewed Library could not be loaded right now. Check your connection, or read it on GitHub.")));
        var retry = el("button", "btn btn-small", t("lp_retry", "Try again"));
        retry.type = "button";
        retry.addEventListener("click", function () { loadReviewed().then(openFromHash); });
        state.appendChild(retry);
        state.appendChild(document.createTextNode(" "));
        state.appendChild(link("https://github.com/enmerasoftware/enterm/tree/main/library", "GitHub"));
      });
  }

  function loadCommunity() {
    commStatus = "loading";
    cState.textContent = t("lp_comm_loading", "Loading community entries…");
    return getJSON(COMMUNITY, { cache: "no-cache", credentials: "omit" })
      .then(function (d) {
        var seen = {};
        community = (d && Array.isArray(d.items) ? d.items : []).slice(0, 2000).map(cleanCommunity).filter(function (it) {
          if (!it || seen[it.id]) return false; seen[it.id] = 1; return true;
        });
        commStatus = "ok";
        update();
      })
      .catch(function () {
        commStatus = "error";
        community = [];
        update();
        cLine.textContent = "";
        cState.textContent = "";
        cState.appendChild(el("p", "", t("lp_comm_error", "Community entries could not be loaded right now. The reviewed Library above still works.")));
        var retry = el("button", "btn btn-small", t("lp_retry", "Try again"));
        retry.type = "button";
        retry.addEventListener("click", function () { loadCommunity().then(openFromHash); });
        cState.appendChild(retry);
      });
  }

  function loadVotes() {
    return getJSON(VOTES, { cache: "no-cache", credentials: "omit" })
      .then(function (d) {
        if (d && d.votes && typeof d.votes === "object" && !Array.isArray(d.votes)) {
          votes = {};
          Object.keys(d.votes).forEach(function (k) { if (k.length < 130) votes[k] = int(d.votes[k]); });
          update();
        }
      })
      .catch(function () {});
  }

  readURL();
  update();
  Promise.all([loadReviewed(), loadCommunity(), loadVotes()]).then(openFromHash);
})();
