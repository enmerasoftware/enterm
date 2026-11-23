import AppKit
import EntermCore
import SwiftUI
import UniformTypeIdentifiers

// A replay of what agents did: one lane per agent, a mark per event, a playhead that runs through them.
// The marks come from the program's own transcript; nothing is recorded for it.

struct TimelineLane: Identifiable {
    let id: String
    let title: String
    let timeline: Timeline
    let positions: [TimeInterval]
    var length: TimeInterval { positions.last ?? 0 }
}

enum TimelineSource {
    /// "session:<id>" for one box, "race:<id>" for every racer of a race.
    static func lanes(for key: String) -> [TimelineLane] {
        let model = AppModel.shared
        var sources: [(id: String, title: String, path: String)] = []
        if key.hasPrefix("session:") {
            let id = String(key.dropFirst("session:".count))
            if let info = model.sessions.first(where: { $0.id == id }), let path = info.transcriptPath {
                sources.append((id, model.name(for: info), path))
            }
        } else if key.hasPrefix("race:"), let race = RaceCenter.shared.race(String(key.dropFirst("race:".count))) {
            for entrant in race.entrants {
                let live = entrant.sessionID.flatMap { id in model.sessions.first { $0.id == id }?.transcriptPath }
                if let path = live ?? entrant.transcript { sources.append((entrant.branch, entrant.title, path)) }
            }
        }
        return sources.map { source in
            let timeline = Timeline.read(path: source.path)
            return TimelineLane(id: source.id, title: source.title, timeline: timeline, positions: timeline.compressed())
        }
    }

    static func color(_ kind: TimelineEvent.Kind) -> NSColor {
        let palette = Theme.palette
        switch kind {
        case .prompt: return palette.need
        case .reply: return palette.text2
        case .edit: return palette.add
        case .command: return palette.g1
        case .read: return palette.g2
        case .tool: return palette.text3
        }
    }

    static func title(_ kind: TimelineEvent.Kind) -> String {
        switch kind {
        case .prompt: return "İstek"
        case .reply: return "Yanıt"
        case .edit: return "Düzenleme"
        case .command: return "Komut"
        case .read: return "Okuma"
        case .tool: return "Araç"
        }
    }

    static func symbol(_ kind: TimelineEvent.Kind) -> String {
        switch kind {
        case .prompt: return "person.fill"
        case .reply: return "text.bubble"
        case .edit: return "pencil"
        case .command: return "terminal"
        case .read: return "doc.text.magnifyingglass"
        case .tool: return "wrench.and.screwdriver"
        }
    }
}

/// Moves the playhead while playing, about thirty times a second; still when paused.
final class TimelinePlayer: ObservableObject {
    @Published var playhead: TimeInterval = 0
    @Published var playing = false
    var speed: Double = 20
    var length: TimeInterval = 0
    private var timer: Timer?
    private var last = Date()

    func toggle() { playing ? pause() : play() }

    func play() {
        if playhead >= length { playhead = 0 }
        playing = true
        last = Date()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        playing = false
        timer?.invalidate()
        timer = nil
    }

    func seek(_ value: TimeInterval) { playhead = min(max(0, value), length) }

    private func step() {
        let now = Date()
        playhead = min(length, playhead + now.timeIntervalSince(last) * speed)
        last = now
        if playhead >= length { pause() }
    }

    deinit { timer?.invalidate() }
}

struct TimelinePage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @StateObject private var player = TimelinePlayer()
    let key: String
    @State private var lanes: [TimelineLane] = []
    @State private var loaded = false
    @State private var selected = 0
    /// How long the whole replay takes, whatever the length of the work.
    @State private var duration = 25.0

    var body: some View {
        PageFrame(title: "Zaman Çizelgesi", wide: true) {
            VStack(alignment: .leading, spacing: 16) {
                if !loaded {
                    Dim("Döküm okunuyor…")
                } else if lanes.allSatisfy({ $0.timeline.events.isEmpty }) {
                    Dim("Bu oturumun dökümü yok ya da boş. Zaman çizelgesi Claude Code ve Codex oturumlarında görünür.")
                } else {
                    controls
                    Panel { tracks.padding(12) }
                    legend
                    HStack(alignment: .top, spacing: 16) {
                        feed.frame(maxWidth: .infinity)
                        files.frame(width: 260)
                    }
                    Dim("Uzun beklemeler 20 saniyeye kısaltılır. Dışa aktarılan dosya istekleri ve komutları içerir; paylaşmadan önce bakın.")
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear { player.pause() }
    }

    private func load() {
        let key = key
        DispatchQueue.global(qos: .userInitiated).async {
            let lanes = TimelineSource.lanes(for: key)
            DispatchQueue.main.async {
                self.lanes = lanes
                player.length = (lanes.map(\.length).max() ?? 0) + 1
                player.speed = max(player.length / duration, 1)
                loaded = true
                // A replay starts by itself once: the point of opening it is to watch.
                if Motion.allowed, !lanes.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { player.play() } } else { player.seek(player.length) }
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 8) {
            Btn(player.playing ? "Duraklat" : "Oynat", kind: .primary, key: "Space", icon: player.playing ? "pause.fill" : "play.fill") { player.toggle() }
                .keyboardShortcut(.space, modifiers: [])
            Btn("Baştan", kind: .plain, icon: "backward.end.fill") { player.seek(0); player.play() }
            Seg(options: [(10.0, "Hızlı"), (25.0, "Normal"), (60.0, "Yavaş")], value: Binding(get: { duration }, set: { duration = $0; player.speed = max(player.length / $0, 1) }))
            Spacer()
            T(Self.clock(player.playhead) + " / " + Self.clock(player.length), color: Theme.palette.text2, style: .secondary).monospacedDigit()
            Btn("HTML Olarak Kaydet", kind: .outline, icon: "square.and.arrow.up") { TimelineExport.save(lanes: lanes, title: lanes.map(\.title).joined(separator: " · ")) }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Tracks

    private var tracks: some View {
        let palette = Theme.palette
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                HStack(spacing: 12) {
                    Button { selected = index } label: {
                        T(lane.title, color: index == selected ? palette.text1 : palette.text3, weight: index == selected ? .semibold : .regular)
                            .lineLimit(1)
                            .frame(width: 130, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    track(lane)
                        .frame(height: 28)
                }
            }
        }
    }

    private func track(_ lane: TimelineLane) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let length = max(player.length, 1)
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    let line = Path(CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2))
                    context.fill(line, with: .color(Color(Theme.palette.hair2)))
                    for (event, position) in zip(lane.timeline.events, lane.positions) {
                        let x = CGFloat(position / length) * size.width
                        let passed = position <= player.playhead
                        let tall: CGFloat = event.kind == .edit || event.kind == .prompt ? size.height : size.height * 0.6
                        let rect = CGRect(x: x - 1, y: (size.height - tall) / 2, width: 2.5, height: tall)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Color(TimelineSource.color(event.kind)).opacity(passed ? 1 : 0.22)))
                    }
                }
                Rectangle()
                    .fill(Color(Theme.palette.text1))
                    .frame(width: 2)
                    .offset(x: CGFloat(player.playhead / length) * width - 1)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                player.pause()
                player.seek(Double(value.location.x / max(width, 1)) * length)
            })
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(TimelineEvent.Kind.allCases, id: \.self) { kind in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1).fill(Color(TimelineSource.color(kind))).frame(width: 8, height: 8)
                    T(TimelineSource.title(kind), color: Theme.palette.text3, style: .secondary)
                }
            }
        }
    }

    // MARK: What happened so far

    private var shownLane: TimelineLane? { lanes.indices.contains(selected) ? lanes[selected] : lanes.first }

    private var passed: [(offset: Int, event: TimelineEvent, at: TimeInterval)] {
        guard let lane = shownLane else { return [] }
        return zip(lane.timeline.events, lane.positions).enumerated()
            .filter { $0.element.1 <= player.playhead }
            .map { ($0.offset, $0.element.0, $0.element.1) }
    }

    private var feed: some View {
        let palette = Theme.palette
        let recent = Array(passed.suffix(9))
        return Panel {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Akış")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recent, id: \.offset) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Symbol(TimelineSource.symbol(item.event.kind), color: TimelineSource.color(item.event.kind), size: 12).frame(width: 16)
                            T(Self.clock(item.at), color: palette.text3, style: .secondary).monospacedDigit().frame(width: 38, alignment: .leading)
                            Text(verbatim: item.event.file.map { ($0 as NSString).lastPathComponent } ?? item.event.text)
                                .font(.system(size: 12))
                                .foregroundColor(Color(item.event.kind == .reply ? palette.text2 : palette.text1))
                                .lineLimit(2)
                        }
                        .transition(Motion.allowed ? .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity) : .identity)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
                .animation(Motion.allowed ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: recent.last?.offset)
                .clipped()
            }
        }
    }

    private var files: some View {
        let palette = Theme.palette
        let edits = passed.filter { $0.event.kind == .edit && $0.event.file != nil }
        var order: [String] = []
        var touches: [String: Int] = [:]
        for edit in edits {
            let file = edit.event.file ?? ""
            if !order.contains(file) { order.append(file) }
            touches[file, default: 0] += 1
        }
        let latest = edits.last?.event.file
        return Panel {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Dosyalar")
                VStack(alignment: .leading, spacing: 6) {
                    if order.isEmpty { Dim("Henüz dosya değişmedi") }
                    ForEach(order, id: \.self) { file in
                        HStack(spacing: 8) {
                            Circle().fill(Color(palette.add)).frame(width: 6, height: 6)
                                .scaleEffect(file == latest && player.playing ? 1.8 : 1)
                            Text(verbatim: (file as NSString).lastPathComponent)
                                .font(.system(size: 12, weight: file == latest ? .semibold : .regular))
                                .foregroundColor(Color(file == latest ? palette.text1 : palette.text2))
                                .lineLimit(1)
                            Spacer()
                            T("×\(touches[file] ?? 0)", color: palette.text3, style: .secondary)
                        }
                        .help(file)
                        .transition(.opacity)
                    }
                }
                .padding(12)
                .animation(Motion.allowed ? .spring(response: 0.3, dampingFraction: 0.6) : nil, value: latest)
            }
        }
    }
}

// MARK: Sharing

/// One HTML file that plays the replay by itself in any browser: no server, no scripts from elsewhere.
enum TimelineExport {
    static func save(lanes: [TimelineLane], title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "enterm-replay.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? html(lanes: lanes, title: title).write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func html(lanes: [TimelineLane], title: String) -> String {
        let data: [[String: Any]] = lanes.map { lane in
            [
                "title": lane.title,
                "events": zip(lane.timeline.events, lane.positions).map { event, at in
                    ["t": (at * 10).rounded() / 10, "k": event.kind.rawValue,
                     "x": String(event.text.prefix(160)), "f": event.file.map { ($0 as NSString).lastPathComponent } ?? ""] as [String: Any]
                },
            ]
        }
        let json = (try? JSONSerialization.data(withJSONObject: ["title": title, "lanes": data]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        // "</" cannot close the script from inside the data.
        let safe = json.replacingOccurrences(of: "</", with: "<\\/")
        return template.replacingOccurrences(of: "__DATA__", with: safe)
    }

    private static let template = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Enterm Replay</title>
    <style>
    :root{--bg:#0b0e0f;--panel:#14181a;--line:rgba(255,255,255,.12);--t1:#eceeec;--t2:#aeb7b3;--t3:#858f8b;
    --prompt:#d8ee4e;--reply:#aeb7b3;--edit:#86d19a;--command:#7fa6ff;--read:#b79cff;--tool:#858f8b}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--t1);font:14px -apple-system,system-ui,sans-serif;padding:24px 16px}
    main{max-width:980px;margin:0 auto}h1{font-size:22px;margin:0 0 4px}p.sub{color:var(--t3);margin:0 0 18px}
    .bar{display:flex;gap:8px;align-items:center;margin-bottom:12px;flex-wrap:wrap}button{background:var(--panel);color:var(--t1);border:1px solid var(--line);border-radius:8px;padding:6px 12px;font:inherit;cursor:pointer}
    button.main{background:#d8ee4e;color:#10140a;border:0;font-weight:600}.clock{margin-left:auto;color:var(--t2);font-variant-numeric:tabular-nums}
    .panel{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:12px}
    .lane{display:flex;align-items:center;gap:12px;height:34px}.lane b{width:130px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-size:13px}
    canvas{flex:1;height:28px;cursor:pointer;min-width:0}.grid{display:grid;grid-template-columns:1fr 260px;gap:16px;margin-top:16px}
    @media(max-width:700px){.grid{grid-template-columns:1fr}}
    .feed div{display:flex;gap:8px;padding:4px 0;animation:in .35s ease-out}.feed i{font-style:normal;color:var(--t3);width:40px;font-variant-numeric:tabular-nums}
    .feed span{overflow:hidden;text-overflow:ellipsis;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical}
    @keyframes in{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}
    .files div{display:flex;gap:8px;align-items:center;padding:3px 0;color:var(--t2);font-size:13px}.files div.hot{color:var(--t1);font-weight:600}
    .dot{width:7px;height:7px;border-radius:50%;background:var(--edit)}.hot .dot{transform:scale(1.7);transition:transform .2s}
    h2{font-size:12px;color:var(--t3);text-transform:uppercase;letter-spacing:.06em;margin:0 0 8px}footer{color:var(--t3);margin-top:18px;font-size:12px}
    @media (prefers-reduced-motion:reduce){.feed div{animation:none}}
    </style></head><body><main>
    <h1 id="title"></h1><p class="sub">Agent replay · made with Enterm</p>
    <div class="bar"><button class="main" id="play">Play</button><button id="restart">Restart</button>
    <button data-s="10">Fast</button><button data-s="25">Normal</button><button data-s="60">Slow</button><span class="clock" id="clock"></span></div>
    <div class="panel" id="lanes"></div>
    <div class="grid"><div class="panel"><h2>Feed</h2><div class="feed" id="feed"></div></div><div class="panel"><h2>Files</h2><div class="files" id="files"></div></div></div>
    <footer>Long pauses are shortened to 20 seconds.</footer></main>
    <script>
    const D=__DATA__;const css=getComputedStyle(document.documentElement);const col=k=>css.getPropertyValue('--'+k).trim();
    document.getElementById('title').textContent=D.title||'Replay';
    const L=Math.max(1,...D.lanes.map(l=>l.events.length?l.events[l.events.length-1].t:0))+1;
    let head=0,speed=Math.max(L/25,1),playing=false,last=0,sel=0;const lanesEl=document.getElementById('lanes');const cs=[];
    D.lanes.forEach((l,i)=>{const d=document.createElement('div');d.className='lane';const b=document.createElement('b');b.textContent=l.title;b.onclick=()=>{sel=i;draw(true)};
    const c=document.createElement('canvas');d.append(b,c);lanesEl.append(d);cs.push(c);
    c.onpointerdown=e=>{const m=ev=>{const r=c.getBoundingClientRect();head=Math.max(0,Math.min(L,(ev.clientX-r.left)/r.width*L));playing=false;draw(true)};m(e);c.onpointermove=ev=>{if(ev.buttons)m(ev)}}});
    const fmt=s=>{s=Math.floor(s);return Math.floor(s/60)+':'+String(s%60).padStart(2,'0')};let shown=-1;
    function draw(force){cs.forEach((c,i)=>{const r=c.getBoundingClientRect(),p=devicePixelRatio||1;c.width=r.width*p;c.height=r.height*p;const g=c.getContext('2d');g.scale(p,p);
    g.fillStyle=col('line')||'#333';g.fillRect(0,r.height/2-1,r.width,2);for(const e of D.lanes[i].events){const x=e.t/L*r.width,h=(e.k=='edit'||e.k=='prompt')?r.height:r.height*.6;
    g.globalAlpha=e.t<=head?1:.22;g.fillStyle=col(e.k);g.fillRect(x-1,(r.height-h)/2,2.5,h)}g.globalAlpha=1;g.fillStyle=col('t1');g.fillRect(head/L*r.width-1,0,2,r.height)});
    document.getElementById('clock').textContent=fmt(head)+' / '+fmt(L);document.getElementById('play').textContent=playing?'Pause':'Play';
    const lane=D.lanes[sel]||{events:[]};const past=lane.events.filter(e=>e.t<=head);if(!force&&past.length===shown)return;shown=past.length;
    const feed=document.getElementById('feed');feed.innerHTML='';for(const e of past.slice(-9)){const d=document.createElement('div');const i=document.createElement('i');i.textContent=fmt(e.t);
    const s=document.createElement('span');s.textContent=e.f||e.x;s.style.color=col(e.k==='reply'?'t2':'t1');s.style.borderLeft='3px solid '+col(e.k);s.style.paddingLeft='6px';d.append(i,s);feed.append(d)}
    const files=document.getElementById('files');files.innerHTML='';const edits=past.filter(e=>e.k==='edit'&&e.f);const hot=edits.length?edits[edits.length-1].f:'';const seen=[];
    for(const e of edits)if(!seen.includes(e.f))seen.push(e.f);for(const f of seen){const d=document.createElement('div');if(f===hot)d.className='hot';const o=document.createElement('span');o.className='dot';
    const n=document.createElement('span');n.textContent=f;d.append(o,n);files.append(d)}}
    function tick(t){if(playing){head=Math.min(L,head+(t-last)/1000*speed);if(head>=L)playing=false}last=t;draw(false);requestAnimationFrame(tick)}
    document.getElementById('play').onclick=()=>{if(head>=L)head=0;playing=!playing};document.getElementById('restart').onclick=()=>{head=0;playing=true;draw(true)};
    document.querySelectorAll('[data-s]').forEach(b=>b.onclick=()=>speed=Math.max(L/+b.dataset.s,1));addEventListener('resize',()=>draw(true));
    playing=!matchMedia('(prefers-reduced-motion: reduce)').matches;requestAnimationFrame(t=>{last=t;tick(t)});
    </script></body></html>
    """
}
