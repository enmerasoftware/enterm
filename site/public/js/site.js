/* Enterm site: shared behaviour (language, GitHub numbers, copy, reveal, menu). No trackers. */
(function () {
  "use strict";
  var doc = document.documentElement;
  doc.classList.add("js");

  var REPO = "enmerasoftware/enterm";
  var LANG_KEY = "enterm-lang";
  var TR = window.ENTERM_TR || {};
  var EN = {};
  var EN_ATTR = {};
  var listeners = [];

  function store(key, value) {
    try {
      if (value === undefined) return localStorage.getItem(key);
      localStorage.setItem(key, value);
    } catch (e) { return null; }
    return null;
  }

  function initialLang() {
    try {
      var q = new URLSearchParams(location.search).get("lang");
      if (q === "tr" || q === "en") return q;
    } catch (e) {}
    var saved = store(LANG_KEY);
    if (saved === "tr" || saved === "en") return saved;
    var nav = (navigator.languages && navigator.languages[0]) || navigator.language || "en";
    return /^tr\b/i.test(nav) ? "tr" : "en";
  }

  var lang = initialLang();

  // Strings in the HTML are English and written by us; the Turkish table lives in tr.js.
  function apply() {
    doc.lang = lang;
    var nodes = document.querySelectorAll("[data-i18n]");
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var key = el.getAttribute("data-i18n");
      if (!(key in EN)) EN[key] = el.innerHTML;
      var val = lang === "tr" && TR[key] != null ? TR[key] : EN[key];
      if (el.innerHTML !== val) el.innerHTML = val;
    }
    var attrs = document.querySelectorAll("[data-i18n-attr]");
    for (var j = 0; j < attrs.length; j++) {
      var a = attrs[j];
      a.getAttribute("data-i18n-attr").split(",").forEach(function (pair) {
        var p = pair.split(":");
        var name = p[0].trim(), k = p[1].trim();
        var id = k + "@" + name;
        if (!(id in EN_ATTR)) EN_ATTR[id] = a.getAttribute(name) || "";
        a.setAttribute(name, lang === "tr" && TR[k] != null ? TR[k] : EN_ATTR[id]);
      });
    }
    var buttons = document.querySelectorAll(".lang button");
    for (var b = 0; b < buttons.length; b++) {
      buttons[b].setAttribute("aria-pressed", buttons[b].getAttribute("data-lang") === lang ? "true" : "false");
    }
    listeners.forEach(function (fn) { try { fn(lang); } catch (e) {} });
  }

  window.Enterm = {
    lang: function () { return lang; },
    t: function (key, en) { return lang === "tr" && TR[key] != null ? TR[key] : en; },
    onLang: function (fn) { listeners.push(fn); },
    reduced: function () { return window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches; },
    toast: toast
  };

  document.addEventListener("click", function (e) {
    var btn = e.target.closest && e.target.closest(".lang button");
    if (!btn) return;
    lang = btn.getAttribute("data-lang") === "tr" ? "tr" : "en";
    store(LANG_KEY, lang);
    apply();
  });

  // ---------- toast ----------
  var toastEl, toastTimer;
  function toast(text) {
    if (!toastEl) {
      toastEl = document.createElement("div");
      toastEl.className = "toast";
      toastEl.setAttribute("role", "status");
      toastEl.setAttribute("aria-live", "polite");
      document.body.appendChild(toastEl);
    }
    toastEl.textContent = text;
    toastEl.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastEl.classList.remove("show"); }, 1800);
  }

  // ---------- copy ----------
  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    return new Promise(function (resolve, reject) {
      var ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "fixed"; ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand("copy") ? resolve() : reject(); } catch (err) { reject(err); }
      document.body.removeChild(ta);
    });
  }
  window.Enterm.copy = function (text, btn) {
    return copyText(text).then(function () {
      toast(window.Enterm.t("copied", "Copied"));
      if (btn) { btn.classList.add("done"); setTimeout(function () { btn.classList.remove("done"); }, 1500); }
    }, function () { toast(window.Enterm.t("copy_failed", "Could not copy; select the text instead")); });
  };
  document.addEventListener("click", function (e) {
    var btn = e.target.closest && e.target.closest("[data-copy]");
    if (!btn) return;
    window.Enterm.copy(btn.getAttribute("data-copy").replace(/\\n/g, "\n"), btn);
  });

  // ---------- header ----------
  var top = document.querySelector(".top");
  function onScroll() { if (top) top.classList.toggle("scrolled", window.scrollY > 8); }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  var menuBtn = document.querySelector(".menu-btn");
  var nav = document.getElementById("nav");
  if (menuBtn && nav) {
    var setMenu = function (open) {
      nav.classList.toggle("open", open);
      menuBtn.setAttribute("aria-expanded", open ? "true" : "false");
    };
    menuBtn.addEventListener("click", function () { setMenu(!nav.classList.contains("open")); });
    nav.addEventListener("click", function (e) { if (e.target.closest("a")) setMenu(false); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && nav.classList.contains("open")) { setMenu(false); menuBtn.focus(); }
    });
  }

  // ---------- reveal ----------
  var reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && !window.Enterm.reduced()) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    for (var r = 0; r < reveals.length; r++) io.observe(reveals[r]);
  } else {
    for (var s = 0; s < reveals.length; s++) reveals[s].classList.add("in");
  }

  // ---------- GitHub numbers (cached, fail silently) ----------
  function cached(key, maxAgeMs, url) {
    var raw = store(key);
    if (raw) {
      try {
        var obj = JSON.parse(raw);
        if (obj && Date.now() - obj.at < maxAgeMs) return Promise.resolve(obj.data);
      } catch (e) {}
    }
    return fetch(url, { headers: { Accept: "application/vnd.github+json" } })
      .then(function (res) { if (!res.ok) throw new Error(res.status); return res.json(); })
      .then(function (data) { store(key, JSON.stringify({ at: Date.now(), data: data })); return data; });
  }

  function compact(n) {
    if (n >= 10000) return Math.round(n / 1000) + "k";
    if (n >= 1000) return (Math.round(n / 100) / 10).toString().replace(/\.0$/, "") + "k";
    return String(n);
  }

  cached("enterm-repo", 30 * 60 * 1000, "https://api.github.com/repos/" + REPO)
    .then(function (repo) {
      var n = repo && typeof repo.stargazers_count === "number" ? repo.stargazers_count : null;
      if (n == null || n < 10) return; // a tiny count says little; show it once it means something
      document.querySelectorAll(".star-count").forEach(function (el) {
        el.textContent = compact(n);
        el.setAttribute("title", n.toLocaleString());
      });
    })
    .catch(function () {});

  cached("enterm-release", 30 * 60 * 1000, "https://api.github.com/repos/" + REPO + "/releases/latest")
    .then(function (rel) {
      var tag = rel && typeof rel.tag_name === "string" ? rel.tag_name : "";
      if (!/^v?\d+(\.\d+){1,3}[\w.-]*$/.test(tag)) return;
      var v = tag.charAt(0) === "v" ? tag : "v" + tag;
      document.querySelectorAll(".version").forEach(function (el) { el.textContent = v; });
      var dmg = (rel.assets || []).filter(function (a) {
        return a && /\.dmg$/i.test(a.name || "") && /^https:\/\/github\.com\//.test(a.browser_download_url || "");
      })[0];
      if (dmg) document.querySelectorAll("[data-dmg]").forEach(function (a) { a.href = dmg.browser_download_url; });
    })
    .catch(function () {});

  apply();
})();
