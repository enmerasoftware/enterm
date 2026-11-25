/* Enterm site: landing page animations. Every demo runs only while it is on screen and the tab is visible,
   and shows its finished state when the visitor prefers reduced motion. */
(function () {
  "use strict";
  var E = window.Enterm;
  var t = E.t;
  var REDUCED = E.reduced();
  var $ = function (sel, root) { return (root || document).querySelector(sel); };

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  // A controller that pauses a demo while it is off screen or the tab is hidden.
  function control(target, onChange) {
    var ctl = { vis: false, gen: 0, waiters: [] };
    ctl.active = function () { return ctl.vis && !document.hidden; };
    ctl.wake = function () {
      if (onChange) onChange(ctl.active());
      if (!ctl.active()) return;
      var w = ctl.waiters; ctl.waiters = [];
      w.forEach(function (f) { f(); });
    };
    ctl.sleep = function (ms) {
      var g = ctl.gen;
      return new Promise(function (resolve) {
        var left = ms;
        function step() {
          if (g !== ctl.gen) return;
          if (!ctl.active()) { ctl.waiters.push(step); return; }
          var t0 = performance.now();
          setTimeout(function () {
            if (g !== ctl.gen) return;
            left -= performance.now() - t0;
            if (!ctl.active() && left > 0) { ctl.waiters.push(step); return; }
            if (left > 4) { step(); return; }
            resolve();
          }, Math.max(0, left));
        }
        step();
      });
    };
    ctl.cancel = function () { ctl.gen++; ctl.waiters = []; };
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (es) {
        ctl.vis = es[0].isIntersecting;
        ctl.wake();
      }, { threshold: 0.15 }).observe(target);
    } else { ctl.vis = true; }
    document.addEventListener("visibilitychange", ctl.wake);
    return ctl;
  }

  function fmt(sec) {
    sec = Math.max(0, sec);
    var m = Math.floor(sec / 60), s = Math.floor(sec % 60);
    return m + ":" + (s < 10 ? "0" : "") + s;
  }

  /* =================== HERO CANVAS =================== */
  (function hero() {
    var stage = $("#stage");
    if (!stage) return;
    var canvas = $("#canvas");
    var boxes = {};
    ["claude", "codex", "gemini", "term"].forEach(function (id) {
      var b = canvas.querySelector('[data-box="' + id + '"]');
      boxes[id] = { el: b, body: b.querySelector(".box-body"), status: b.querySelector(".status") };
    });
    var approve = $("#approve");
    var link = canvas.querySelector(".link");
    var port = canvas.querySelector(".port");
    var usage = stage.querySelector(".usage b i");

    var STATUS = {
      run: ["st_running", "Running"], wait: ["st_waiting", "Waiting"],
      need: ["st_need", "Needs you"], done: ["st_done", "Done"]
    };
    function setStatus(id, kind) {
      var s = boxes[id].status;
      if (!s) return;
      s.className = "status s-" + kind;
      s.setAttribute("data-kind", kind);
      var em = s.querySelector("em");
      em.removeAttribute("data-i18n");
      em.textContent = t(STATUS[kind][0], STATUS[kind][1]);
    }
    E.onLang(function () {
      Object.keys(boxes).forEach(function (id) {
        var s = boxes[id].status;
        if (s && s.getAttribute("data-kind")) setStatus(id, s.getAttribute("data-kind"));
      });
    });

    // A line is a list of [class, text] parts; text is ours, set with textContent.
    function line(id, cls, parts) {
      var body = boxes[id].body;
      var cur = body.querySelector(".cur");
      if (cur) cur.remove();
      var ln = el("div", "ln " + (cls || ""));
      parts.forEach(function (p) {
        if (typeof p === "string") ln.appendChild(document.createTextNode(p));
        else ln.appendChild(el("span", p[0], p[1]));
      });
      body.appendChild(ln);
      while (body.scrollHeight > body.clientHeight + 2 && body.children.length > 1) body.removeChild(body.firstChild);
      return ln;
    }
    function cursor(id) { var last = boxes[id].body.lastElementChild; if (last) last.appendChild(el("span", "cur")); }

    var ctl = control(stage, function (on) { stage.classList.toggle("live", on); });

    async function typePrompt(id, mark, text) {
      var ln = line(id, "", [["pr", mark], " "]);
      var span = el("span");
      ln.appendChild(span);
      for (var i = 1; i <= text.length; i++) {
        span.textContent = text.slice(0, i);
        await ctl.sleep(18 + Math.random() * 30);
      }
    }

    function reset() {
      Object.keys(boxes).forEach(function (id) {
        boxes[id].body.textContent = "";
        boxes[id].el.classList.remove("need", "done");
      });
      setStatus("claude", "run"); setStatus("codex", "run"); setStatus("gemini", "wait");
      approve.hidden = true; approve.classList.remove("show", "ok");
      approve.querySelector(".allow").classList.remove("press");
      link.classList.remove("on");
      port.hidden = true;
      usage.style.width = "38%";
    }

    function finalState() {
      reset();
      line("claude", "", [["pr", "❯"], " Add a password reset page"]);
      line("claude", "bul", ["Reading the auth module first."]);
      line("claude", "dim", ["Edit Sources/Auth/PasswordReset.swift ", ["add", "+48"]]);
      line("claude", "dim", ["Bash swift test --filter PasswordResetTests"]);
      line("claude", "bul ok", ["Done: reset page, mailer and tests are in."]);
      line("codex", "", [["pr", "❯"], " Find why /orders is slow"]);
      line("codex", "dim", ["Edited src/orders/query.ts ", ["add", "+18"], " ", ["del", "−6"]]);
      line("codex", "bul ok", ["Added an index and batched the lookup."]);
      line("gemini", "", [["pr", "❯"], " Update the install steps in the README"]);
      line("gemini", "bul", ["Wants to run: npm run build"]);
      line("term", "", [["pr", "$"], " npm run dev"]);
      line("term", "dim", ["➜ Local: http://localhost:5173/"]);
      setStatus("claude", "done"); setStatus("codex", "done"); setStatus("gemini", "need");
      boxes.gemini.el.classList.add("need");
      port.hidden = false;
      link.classList.add("on");
    }

    async function run() {
      var g = ctl.gen;
      while (g === ctl.gen) {
        reset();
        await ctl.sleep(500);
        await typePrompt("claude", "❯", "Add a password reset page");
        await typePrompt("codex", "❯", "Find why /orders is slow");
        await typePrompt("term", "$", "npm run dev");
        await typePrompt("gemini", "❯", "Update the install steps in the README");
        setStatus("gemini", "run");
        var S = ctl.sleep;
        await S(400); line("claude", "bul", ["Reading the auth module first."]);
        await S(350); line("term", "dim", ["> vite"]);
        await S(300); line("claude", "dim", ["Read Sources/Auth/Login.swift"]);
        await S(300); line("codex", "bul", ["Ran rg \"SELECT\" src/orders"]);
        await S(350); line("term", "dim", ["➜ Local: http://localhost:5173/"]); port.hidden = false;
        await S(300); line("gemini", "bul", ["Reading README.md"]);
        await S(400); line("codex", "dim", ["Explored 4 files"]);
        await S(300); line("claude", "dim", ["Grep resetToken"]);
        await S(400); link.classList.add("on");
        line("claude", "dim", ["Edit Sources/Auth/PasswordReset.swift ", ["add", "+48"]]);
        await S(450);
        line("gemini", "warn", ["Wants to run: npm run build"]);
        setStatus("gemini", "need"); boxes.gemini.el.classList.add("need");
        await S(500);
        approve.hidden = false;
        await S(30); approve.classList.add("show");
        await S(500); line("codex", "dim", ["Edited src/orders/query.ts ", ["add", "+18"], " ", ["del", "−6"]]);
        await S(500); line("claude", "dim", ["Edit Sources/Views/ResetPage.swift ", ["add", "+31"]]);
        await S(500); approve.querySelector(".allow").classList.add("press");
        await S(260); approve.classList.add("ok");
        boxes.gemini.el.classList.remove("need"); setStatus("gemini", "run");
        line("gemini", "ok", ["✓ Allowed"]);
        await S(600); line("codex", "bul", ["Ran npm test"]);
        await S(300); line("gemini", "dim", ["Bash npm run build"]);
        await S(400); line("codex", "dim ok", ["42 passed"]);
        await S(300); approve.classList.remove("show");
        await S(300); approve.hidden = true;
        line("claude", "dim", ["Bash swift test --filter PasswordResetTests"]);
        usage.style.width = "46%";
        await S(500); line("gemini", "dim", ["Edit README.md ", ["add", "+12"], " ", ["del", "−9"]]);
        await S(500); line("codex", "bul ok", ["Added an index and batched the lookup."]);
        setStatus("codex", "done"); boxes.codex.el.classList.add("done"); cursor("codex");
        await S(600); line("gemini", "bul ok", ["Done: install steps updated."]);
        setStatus("gemini", "done"); boxes.gemini.el.classList.add("done"); cursor("gemini");
        await S(700); line("claude", "bul ok", ["Done: reset page, mailer and tests are in."]);
        setStatus("claude", "done"); boxes.claude.el.classList.add("done"); cursor("claude");
        cursor("term");
        await S(4200);
      }
    }

    if (REDUCED) finalState(); else run();

    // Tilt the stage flat as it scrolls into view.
    if (!REDUCED) {
      var tiltBox = $("#stage-tilt");
      var ticking = false;
      var update = function () {
        ticking = false;
        if (window.innerWidth < 760) { stage.style.setProperty("--tilt", "0deg"); stage.style.setProperty("--scale", "1"); return; }
        var r = tiltBox.getBoundingClientRect();
        var vh = window.innerHeight;
        var p = Math.min(1, Math.max(0, (vh - r.top) / (vh * 0.85)));
        stage.style.setProperty("--tilt", (18 * (1 - p)).toFixed(2) + "deg");
        stage.style.setProperty("--scale", (0.93 + 0.07 * p).toFixed(3));
      };
      window.addEventListener("scroll", function () { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
      window.addEventListener("resize", update);
      update();
    }
  })();

  /* =================== RACE =================== */
  (function race() {
    var root = $("#race-demo");
    if (!root) return;
    var lanesEl = $("#race-lanes"), rowsEl = $("#race-rows"), results = $("#race-results"), merge = $("#race-merge");
    var SLUG = "add-a-password-reset-page";
    var racers = [
      { id: "claude", name: "Claude Code", c: "var(--lime)", finish: 19, files: 6, add: 91, del: 0, test: "pass", ph: 0.3 },
      { id: "codex", name: "Codex", c: "var(--blue)", finish: 15, files: 4, add: 57, del: 0, test: "fail", ph: 1.7 },
      { id: "gemini", name: "Gemini", c: "var(--violet)", finish: 23, files: 5, add: 74, del: 3, test: "pass", ph: 2.9 }
    ];
    var END = 24.5;
    var MEDAL_TXT = ["1", "2", "3"];
    var MEDAL_BG = ["radial-gradient(circle at 35% 30%, #fff3c4, var(--gold))", "radial-gradient(circle at 35% 30%, #fff, var(--silver))", "radial-gradient(circle at 35% 30%, #ffe0c8, var(--bronze))"];
    var order = racers.slice().sort(function (a, b) { return a.finish - b.finish; });
    order.forEach(function (r, i) { r.place = i; });

    racers.forEach(function (r) {
      var lane = el("div", "lane");
      lane.style.setProperty("--c", r.c);
      var top = el("div", "lane-top");
      var sp = el("span", "spark"); sp.style.setProperty("--c", r.c);
      top.appendChild(sp);
      top.appendChild(el("b", "", r.name));
      top.appendChild(el("span", "wt", "yaris/" + SLUG + "-" + r.id));
      r.st = el("span", "lane-st");
      top.appendChild(r.st);
      var row = el("div", "lane-row");
      r.stats = el("span", "lane-stats");
      var track = el("div", "track");
      r.trail = el("span", "trail");
      r.runner = el("span", "runner");
      r.medal = el("span", "medal m" + (r.place + 1), MEDAL_TXT[r.place]);
      track.appendChild(r.trail); track.appendChild(el("span", "flag")); track.appendChild(r.runner); track.appendChild(r.medal);
      row.appendChild(r.stats); row.appendChild(track);
      lane.appendChild(top); lane.appendChild(row);
      r.lane = lane;
      lanesEl.appendChild(lane);
    });

    var PLACE = [["place1", "1st"], ["place2", "2nd"], ["place3", "3rd"]];
    function statusText(r, done) {
      return done ? t("race_finished", "Finished") + " · " + t(PLACE[r.place][0], PLACE[r.place][1]) : t("st_running", "Running");
    }

    var simT = 0;
    function progress(r, s) {
      var p = Math.min(1, s / r.finish);
      // uneven pace: agents read first, then write in bursts
      var wob = 0.05 * Math.sin(p * 8 + r.ph) * (1 - p) * p * 4;
      return Math.min(1, Math.max(0, Math.pow(p, 1.12) + wob));
    }
    function drawLanes() {
      racers.forEach(function (r) {
        var done = simT >= r.finish;
        var pos = done ? 1 : progress(r, simT);
        var pct = (pos * 100).toFixed(2);
        r.runner.style.left = "calc((100% - 18px) * " + pos.toFixed(4) + ")";
        r.trail.style.width = "calc((100% - 18px) * " + pos.toFixed(4) + ")";
        r.runner.style.opacity = done ? "0" : "1";
        var files = Math.round(r.files * Math.pow(pos, 0.8));
        var add = Math.round(r.add * pos), del = Math.round(r.del * pos);
        r.stats.textContent = "";
        r.stats.appendChild(document.createTextNode(fmt(Math.min(simT, r.finish)) + " · " + files + " " + t("race_files", "files") + " · "));
        r.stats.appendChild(el("span", "add", "+" + add));
        r.stats.appendChild(document.createTextNode(" −" + del));
        r.st.textContent = statusText(r, done);
        r.medal.classList.toggle("show", done);
        r.lane.classList.toggle("fin", done);
        void pct;
      });
    }

    var TEST = { run: ["race_testing", "Testing"], pass: ["race_pass", "Tests Passed"], fail: ["race_fail", "Tests Failed"] };
    var resultState = { shown: false, tests: {}, picked: false, merged: 0 };
    function drawResults() {
      rowsEl.textContent = "";
      results.classList.toggle("on", resultState.shown);
      if (!resultState.shown) { merge.textContent = ""; return; }
      order.forEach(function (r) {
        var row = el("div", "rrow" + (resultState.picked && r.id === "claude" ? " win" : ""));
        var num = el("span", "rnum", String(r.place + 1)); num.style.background = MEDAL_BG[r.place];
        row.appendChild(num);
        var who = el("span");
        who.appendChild(el("span", "rname", r.name));
        who.appendChild(document.createTextNode(" "));
        who.appendChild(el("span", "rmeta", fmt(r.finish) + " · " + r.files + " " + t("race_files", "files") + " · +" + r.add + " −" + r.del));
        row.appendChild(who);
        var st = resultState.tests[r.id];
        if (st) row.appendChild(el("span", "rtest " + (st === "run" ? "run" : st), (st === "pass" ? "✓ " : st === "fail" ? "✕ " : "") + t(TEST[st][0], TEST[st][1])));
        else row.appendChild(el("span", "rtest", ""));
        var pick = el("span", "rpick" + (resultState.press && r.id === "claude" ? " press" : ""), t("race_pick", "Pick Winner"));
        row.appendChild(pick);
        rowsEl.appendChild(row);
      });
      merge.textContent = "";
      if (resultState.merged >= 1) merge.appendChild(el("div", "", "$ git merge --no-ff yaris/" + SLUG + "-claude"));
      if (resultState.merged >= 2) merge.appendChild(el("div", "", "✓ " + t("race_merged", "Merged. The race's worktrees and branches are removed.")));
    }
    E.onLang(function () { drawLanes(); drawResults(); });

    var ctl = control(root);

    function frame(dur) {
      // advance the race clock with requestAnimationFrame while visible
      return new Promise(function (resolve) {
        var g = ctl.gen, last = null;
        function tick(now) {
          if (g !== ctl.gen) return;
          if (!ctl.active()) { last = null; ctl.waiters.push(function () { requestAnimationFrame(tick); }); return; }
          if (last != null) simT = Math.min(END, simT + (now - last) / 1000 * (END / dur));
          last = now;
          drawLanes();
          if (simT >= END) resolve(); else requestAnimationFrame(tick);
        }
        requestAnimationFrame(tick);
      });
    }

    async function run() {
      ctl.cancel();
      var g = ctl.gen;
      simT = 0;
      resultState = { shown: false, tests: {}, picked: false, merged: 0 };
      drawLanes(); drawResults();
      await ctl.sleep(400);
      await frame(8.5);
      if (g !== ctl.gen) return;
      await ctl.sleep(600);
      resultState.shown = true; drawResults();
      for (var i = 0; i < order.length; i++) {
        await ctl.sleep(350);
        resultState.tests[order[i].id] = "run"; drawResults();
      }
      for (var j = 0; j < order.length; j++) {
        await ctl.sleep(700);
        resultState.tests[order[j].id] = order[j].test; drawResults();
      }
      await ctl.sleep(1100);
      resultState.press = true; drawResults();
      await ctl.sleep(300);
      resultState.press = false; resultState.picked = true; resultState.merged = 1; drawResults();
      await ctl.sleep(900);
      resultState.merged = 2; drawResults();
      await ctl.sleep(7000);
      if (g === ctl.gen) run();
    }

    function finalState() {
      simT = END; drawLanes();
      resultState = { shown: true, tests: { claude: "pass", codex: "fail", gemini: "pass" }, picked: true, merged: 2 };
      drawResults();
    }

    $("#race-replay").addEventListener("click", function () { if (REDUCED) finalState(); else run(); });

    if (REDUCED) { finalState(); return; }
    simT = 0; drawLanes(); drawResults();
    // start the first time it comes into view
    var started = false;
    new IntersectionObserver(function (es) {
      if (es[0].isIntersecting && !started) { started = true; run(); }
    }, { threshold: 0.35 }).observe(root);
  })();

  /* =================== TIMELINE =================== */
  (function timeline() {
    var root = $("#tl-demo");
    if (!root) return;
    var TOTAL = 20;
    var KIND = {
      prompt: { c: "var(--lime)", h: "70%" }, reply: { c: "var(--silver)", h: "42%" }, edit: { c: "var(--green)", h: "70%" },
      command: { c: "var(--blue)", h: "42%" }, read: { c: "var(--violet)", h: "42%" }
    };
    var lanes = [
      { name: "Claude Code", ev: [
        [0, "prompt", "Add a password reset page"], [0.8, "reply", "Reading the auth module first."],
        [1.3, "read", "Read Sources/Auth/Login.swift"], [2.7, "read", "Grep resetToken"],
        [5.5, "edit", "PasswordReset.swift"], [7.4, "edit", "ResetMailer.swift"], [9.6, "edit", "ResetPage.swift"],
        [10.4, "edit", "PasswordResetTests.swift"], [12.1, "command", "swift test --filter PasswordResetTests"],
        [14.2, "edit", "TokenStore.swift"], [16.4, "command", "swift test"], [18.6, "edit", "PasswordReset.swift"],
        [19.4, "reply", "Done: reset page, mailer and tests are in, all tests pass."]
      ] },
      { name: "Codex", ev: [
        [0, "prompt", "Add a password reset page"], [1.0, "read", "Read Sources/Auth/Login.swift"],
        [2.9, "read", "rg resetToken"], [5.8, "edit", "PasswordReset.swift"], [7.6, "edit", "ResetMailer.swift"],
        [9.9, "edit", "ResetPage.swift"], [11.6, "command", "swift test --filter PasswordResetTests"],
        [13.5, "edit", "ResetPage.swift"], [14.6, "reply", "Done: reset page and mailer are in."]
      ] }
    ];
    var lanesEl = $("#tl-lanes"), feed = $("#tl-feed"), filesEl = $("#tl-files"), clock = $("#tl-clock");
    var playBtn = $("#tl-play");
    var SPEEDS = { fast: 7, normal: 14, slow: 28 };
    var speed = "normal", pos = 0, playing = false, sel = 0, raf = 0;

    lanes.forEach(function (lane, i) {
      var row = el("div", "tl-lane");
      var name = el("button", "tl-name", lane.name);
      name.type = "button";
      name.addEventListener("click", function () { sel = i; lastFeed = -1; render(); });
      row.appendChild(name);
      var track = el("div", "tl-track");
      lane.marks = lane.ev.map(function (e) {
        var m = el("span", "mk");
        m.style.left = (e[0] / TOTAL * 100) + "%";
        m.style.setProperty("--c", KIND[e[1]].c);
        m.style.setProperty("--h", KIND[e[1]].h);
        track.appendChild(m);
        return m;
      });
      lane.head = el("span", "playhead");
      track.appendChild(lane.head);
      row.appendChild(track);
      lane.nameEl = name; lane.track = track;
      lanesEl.appendChild(row);
    });

    var lastFeed = -1;
    function render() {
      lanes.forEach(function (lane, i) {
        lane.nameEl.classList.toggle("sel", i === sel);
        lane.nameEl.setAttribute("aria-pressed", i === sel ? "true" : "false");
        lane.head.style.left = (pos / TOTAL * 100) + "%";
        lane.ev.forEach(function (e, k) {
          var lit = e[0] <= pos + 0.001;
          lane.marks[k].classList.toggle("lit", lit);
          lane.marks[k].classList.toggle("hot", lit && pos - e[0] < 0.7);
        });
      });
      clock.textContent = fmt(pos) + " / " + fmt(TOTAL);
      lanesEl.setAttribute("aria-valuenow", pos.toFixed(1));
      lanesEl.setAttribute("aria-valuetext", fmt(pos));
      var shown = lanes[sel].ev.filter(function (e) { return e[0] <= pos + 0.001; });
      if (shown.length !== lastFeed) {
        lastFeed = shown.length;
        feed.textContent = "";
        shown.slice(-7).forEach(function (e) {
          var li = el("li", e[1] === "command" ? "f-cmd" : e[1] === "read" ? "f-read" : "");
          var k = el("span", "k"); k.style.setProperty("--c", KIND[e[1]].c);
          li.appendChild(k);
          li.appendChild(el("time", "", fmt(e[0])));
          li.appendChild(el("span", "", e[2]));
          feed.appendChild(li);
        });
        filesEl.textContent = "";
        var counts = {}, orderF = [], latest = null;
        shown.forEach(function (e) {
          if (e[1] !== "edit") return;
          if (!counts[e[2]]) { counts[e[2]] = 0; orderF.push(e[2]); }
          counts[e[2]]++; latest = e[2];
        });
        orderF.forEach(function (f) {
          var li = el("li", f === latest ? "hot" : "");
          li.appendChild(el("span", "", f));
          li.appendChild(el("b", "", "×" + counts[f]));
          filesEl.appendChild(li);
        });
      }
    }

    function setPlaying(on) {
      playing = on;
      playBtn.querySelector(".tl-play-ic").textContent = on ? "❚❚" : "▶";
      var lbl = playBtn.querySelector(".tl-play-label");
      lbl.removeAttribute("data-i18n");
      lbl.textContent = on ? t("tl_pause", "Pause") : t("tl_play", "Play");
      cancelAnimationFrame(raf);
      if (on) {
        if (pos >= TOTAL) { pos = 0; lastFeed = -1; }
        var last = null;
        var tick = function (now) {
          if (!playing) return;
          if (!ctl.active()) { last = null; ctl.waiters.push(function () { raf = requestAnimationFrame(tick); }); return; }
          if (last != null) pos = Math.min(TOTAL, pos + (now - last) / 1000 * (TOTAL / SPEEDS[speed]));
          last = now;
          render();
          if (pos >= TOTAL) setPlaying(false); else raf = requestAnimationFrame(tick);
        };
        raf = requestAnimationFrame(tick);
      }
    }
    E.onLang(function () { setPlaying(playing); });

    var ctl = control(root);

    playBtn.addEventListener("click", function () { setPlaying(!playing); });
    $("#tl-restart").addEventListener("click", function () { pos = 0; lastFeed = -1; render(); setPlaying(!REDUCED || playing); });
    root.querySelectorAll("[data-speed]").forEach(function (b) {
      b.addEventListener("click", function () {
        speed = b.getAttribute("data-speed");
        root.querySelectorAll("[data-speed]").forEach(function (o) { o.setAttribute("aria-pressed", o === b ? "true" : "false"); });
      });
    });

    // scrubbing
    function seek(clientX) {
      var r = lanes[0].track.getBoundingClientRect();
      pos = Math.min(TOTAL, Math.max(0, (clientX - r.left) / r.width * TOTAL));
      lastFeed = -1;
      render();
    }
    var dragging = false;
    lanesEl.addEventListener("pointerdown", function (e) {
      if (e.target.closest(".tl-name")) return;
      dragging = true;
      try { lanesEl.setPointerCapture(e.pointerId); } catch (err) {}
      setPlaying(false);
      seek(e.clientX);
    });
    lanesEl.addEventListener("pointermove", function (e) { if (dragging) seek(e.clientX); });
    ["pointerup", "pointercancel"].forEach(function (n) { lanesEl.addEventListener(n, function () { dragging = false; }); });
    lanesEl.addEventListener("keydown", function (e) {
      var k = e.key, handled = true;
      if (k === "ArrowRight" || k === "ArrowUp") pos = Math.min(TOTAL, pos + 1);
      else if (k === "ArrowLeft" || k === "ArrowDown") pos = Math.max(0, pos - 1);
      else if (k === "Home") pos = 0;
      else if (k === "End") pos = TOTAL;
      else if (k === " " || k === "Enter") { setPlaying(!playing); }
      else handled = false;
      if (handled) { e.preventDefault(); if (k !== " " && k !== "Enter") { setPlaying(false); lastFeed = -1; render(); } }
    });

    if (REDUCED) { pos = TOTAL; render(); return; }
    render();
    var started = false;
    new IntersectionObserver(function (es) {
      if (es[0].isIntersecting && !started) { started = true; setPlaying(true); }
    }, { threshold: 0.4 }).observe(root);
  })();

  /* =================== DESIGN CHECK =================== */
  (function design() {
    var root = $("#dc-demo");
    if (!root) return;
    var rowsEl = $("#dc-rows"), typed = $("#dc-typed");
    var CMD = "npx --yes @enmera/ai-design-check@latest";
    var AREAS = [
      { k: "dc_area_a11y", en: "accessibility", c: "var(--coral)", sev: "err" },
      { k: "dc_area_layout", en: "layout", c: "var(--gold)", sev: "warn" },
      { k: "dc_area_type", en: "type", c: "var(--gold)", sev: "warn" },
      { k: "dc_area_visual", en: "visual language", c: "var(--gold)", sev: "warn" },
      { k: "dc_area_copy", en: "copy", c: "var(--blue)", sev: "note" }
    ];
    var STAGES = [[3, 5, 4, 6, 2], [3, 1, 1, 4, 2], [0, 0, 0, 1, 1]];
    var counts = null;
    var rows = AREAS.map(function (a) {
      var r = el("div", "dc-row");
      r.label = el("span", "", a.en);
      var bar = el("span", "bar"); r.fill = el("i"); r.fill.style.setProperty("--c", a.c); bar.appendChild(r.fill);
      r.num = el("b", "", "");
      r.appendChild(r.label); r.appendChild(bar); r.appendChild(r.num);
      return r;
    });
    function draw() {
      rowsEl.textContent = "";
      if (!counts) { ["dc-err", "dc-warn", "dc-note"].forEach(function (id) { $("#" + id).textContent = "0"; }); return; }
      var tot = { err: 0, warn: 0, note: 0 };
      AREAS.forEach(function (a, i) {
        var r = rows[i];
        r.label.textContent = t(a.k, a.en);
        r.num.textContent = String(counts[i]);
        r.fill.style.width = Math.min(100, counts[i] / 6 * 100) + "%";
        tot[a.sev] += counts[i];
        rowsEl.appendChild(r);
      });
      $("#dc-err").textContent = tot.err; $("#dc-warn").textContent = tot.warn; $("#dc-note").textContent = tot.note;
    }
    E.onLang(draw);
    var acts = root.querySelectorAll(".dc-act");
    function act(step, state) { acts.forEach(function (a) { if (+a.getAttribute("data-step") === step) { a.classList.remove("on", "did"); if (state) a.classList.add(state); } }); }
    var ctl = control(root);

    async function run() {
      var g = ctl.gen;
      while (g === ctl.gen) {
        counts = null; draw();
        acts.forEach(function (a) { a.classList.remove("on", "did"); });
        typed.textContent = "";
        await ctl.sleep(500);
        for (var i = 1; i <= CMD.length; i++) { typed.textContent = CMD.slice(0, i); await ctl.sleep(28); }
        await ctl.sleep(500);
        counts = [0, 0, 0, 0, 0]; draw();
        await ctl.sleep(60);
        counts = STAGES[0].slice(); draw();
        await ctl.sleep(1800);
        act(1, "on"); await ctl.sleep(900); act(1, "did");
        act(2, "on"); await ctl.sleep(500);
        counts = STAGES[1].slice(); draw(); act(2, "did");
        await ctl.sleep(1500);
        act(3, "on"); await ctl.sleep(1100);
        counts = STAGES[2].slice(); draw(); act(3, "did");
        await ctl.sleep(1200);
        act(4, "on"); await ctl.sleep(1400); act(4, "");
        await ctl.sleep(3000);
      }
    }
    if (REDUCED) { counts = STAGES[2].slice(); draw(); act(1, "did"); act(2, "did"); act(3, "did"); return; }
    run();
  })();

  /* =================== PHONE =================== */
  (function phone() {
    var root = $("#phone-demo");
    if (!root) return;
    var note = $("#ph-note"), face = root.querySelector(".ph-face"), live = $("#ph-live"), bar = live.querySelector(".ph-bar i");
    var allow = root.querySelector(".ph-allow");
    var ctl = control(root);
    function reset() { note.classList.remove("show", "ok"); face.classList.remove("show"); live.classList.remove("show"); allow.classList.remove("press"); bar.style.width = "12%"; }
    async function run() {
      var g = ctl.gen;
      while (g === ctl.gen) {
        reset();
        await ctl.sleep(900);
        note.classList.add("show");
        await ctl.sleep(1700);
        allow.classList.add("press");
        await ctl.sleep(250);
        face.classList.add("show");
        await ctl.sleep(1000);
        face.classList.remove("show");
        note.classList.add("ok");
        await ctl.sleep(700);
        live.classList.add("show");
        await ctl.sleep(100);
        bar.style.width = "72%";
        await ctl.sleep(3800);
        note.classList.remove("show"); live.classList.remove("show");
        await ctl.sleep(800);
      }
    }
    if (REDUCED) { note.classList.add("show", "ok"); live.classList.add("show"); bar.style.width = "72%"; return; }
    run();
  })();

  /* =================== VIDEO =================== */
  (function video() {
    var v = $("#hero-video"), btn = $("#video-toggle");
    if (!v) return;
    if (REDUCED) { v.controls = true; return; }
    var userPaused = false;
    function label() {
      var s = btn.querySelector("span");
      s.removeAttribute("data-i18n");
      s.textContent = v.paused ? t("video_play", "Play video") : t("video_pause", "Pause video");
    }
    btn.addEventListener("click", function () {
      if (v.paused) { userPaused = false; v.play().catch(function () {}); } else { userPaused = true; v.pause(); }
    });
    v.addEventListener("play", label); v.addEventListener("pause", label);
    E.onLang(label);
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (es) {
        if (es[0].isIntersecting) {
          btn.hidden = false;
          if (!userPaused) v.play().catch(function () { v.controls = true; btn.hidden = true; });
        } else if (!v.paused) v.pause();
      }, { threshold: 0.35 }).observe(v);
    } else { v.controls = true; }
  })();

  /* =================== LIBRARY COUNT =================== */
  (function libCount() {
    var out = $("#lib-count");
    if (!out) return;
    var counts = null;
    function draw() {
      if (!counts) return;
      out.textContent = t("lib_count", "{n} reviewed items today: {p} prompts, {r} race tasks, {s} skill packs.")
        .replace("{n}", counts.all).replace("{p}", counts.prompt).replace("{r}", counts.race).replace("{s}", counts.skill);
    }
    E.onLang(draw);
    fetch("https://raw.githubusercontent.com/enmerasoftware/enterm/main/library/index.json")
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (d) {
        var items = (d && Array.isArray(d.items)) ? d.items : [];
        counts = { all: items.length, prompt: 0, race: 0, skill: 0 };
        items.forEach(function (i) { if (i && counts[i.kind] != null) counts[i.kind]++; });
        if (counts.all) draw();
      })
      .catch(function () {});
  })();

  /* card glow follows the pointer */
  document.querySelectorAll(".card").forEach(function (c) {
    c.addEventListener("pointermove", function (e) {
      var r = c.getBoundingClientRect();
      c.style.setProperty("--mx", (e.clientX - r.left) + "px");
      c.style.setProperty("--my", (e.clientY - r.top) + "px");
    });
  });
})();
