import AppKit
import EntermCore
import SwiftUI

/// Runs a command here or on the server. Files and Git use the same screens for both.
struct CommandRunner {
    var remote: RemoteProject?
    var folder: String

    private static var sshPath: String {
#if ENTERM_TEST_DRIVER
        if let path = ProcessInfo.processInfo.environment["ENTERM_SSH"] { return path }
#endif
        return "/usr/bin/ssh"
    }

    func run(_ words: [String], input: Data? = nil) -> (ok: Bool, output: String) {
        let process = Process()
        if let remote {
            process.executableURL = URL(fileURLWithPath: Self.sshPath)
            let line = "cd \(CommandRunner.remoteQuote(folder)) && " + words.map(CommandRunner.remoteQuote).joined(separator: " ")
            process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", remote.host, line]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = words
            process.currentDirectoryURL = URL(fileURLWithPath: folder)
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let inputPipe = Pipe()
        if input != nil { process.standardInput = inputPipe }
        guard (try? process.run()) != nil else { return (false, "Başlatılamadı") }
        if let input {
            try? inputPipe.fileHandleForWriting.write(contentsOf: input)
            try? inputPipe.fileHandleForWriting.close()
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }

    /// `~` stays unquoted so the server's shell can expand it.
    static func remoteQuote(_ text: String) -> String {
        if text == "~" { return "~" }
        if text.hasPrefix("~/") { return "~/" + remoteQuote(String(text.dropFirst(2))) }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func listing(_ directory: String) -> (ok: Bool, items: [(name: String, directory: Bool)]) {
        if remote == nil {
            guard let found = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return (false, []) }
            let items = found.map { url -> (name: String, directory: Bool) in
                (url.lastPathComponent, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            }
            return (true, items.sorted { $0.name.lowercased() < $1.name.lowercased() })
        }
        let result = run(["ls", "-1p", directory])
        guard result.ok else { return (false, []) }
        let items = result.output.split(separator: "\n").map { line -> (name: String, directory: Bool) in
            line.hasSuffix("/") ? (String(line.dropLast()), true) : (String(line), false)
        }
        return (true, items)
    }

    func readText(_ path: String) -> String? {
        if remote == nil {
            guard let data = FileManager.default.contents(atPath: path), data.count < 2_000_000 else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let size = run(["wc", "-c", path])
        guard size.ok, let bytes = Int(size.output.split(separator: " ").first ?? ""), bytes < 2_000_000 else { return nil }
        let result = run(["cat", path])
        return result.ok ? result.output : nil
    }

    func writeText(_ text: String, to path: String) -> Bool {
        if remote == nil {
            return (try? text.write(toFile: path, atomically: true, encoding: .utf8)) != nil
        }
        // The file is written through a temporary name, so a dropped connection cannot leave half a file.
        let temporary = path + ".enterm-tmp"
        guard run(["tee", temporary], input: Data(text.utf8)).ok else { return false }
        return run(["mv", temporary, path]).ok
    }
}

struct RemoteProject: Equatable {
    var host: String
    var folder: String

    /// Opens the server's shell in this folder as a normal terminal session.
    func open() {
        let model = AppModel.shared
        var spec = SessionSpec(name: "\(host):\(folder)", tool: .terminal, rows: 30, cols: 100)
        let target = NotFoundActions.shellQuote(host)
        let remote = "cd \(CommandRunner.remoteQuote(folder)) && exec \\$SHELL -l"
        spec.env = ["ENTERM_STARTUP": "ssh -t \(target) \"\(remote)\""]
        let project = self
        model.create(spec) { info in
            model.remotes[info.number] = project
        }
    }
}

extension AppModel {
    var currentRunner: CommandRunner {
        if let number = focused, let remote = remotes[number] {
            return CommandRunner(remote: remote, folder: remote.folder)
        }
        return CommandRunner(remote: nil, folder: focusedInfo?.cwd ?? NSHomeDirectory())
    }
}

struct RemoteLostDialog: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let number: UInt32
    @ObservedObject var model = AppModel.shared
    var body: some View {
        let remote = model.remotes[number]
        Panel(border: Theme.palette.err) {
            PanelHeader(title: "Bağlantı Koptu") { T("✕ Bağlantı Yok", color: Theme.palette.err, bold: true) }
            VStack(alignment: .leading, spacing: 12) {
                Dim("İnternet ya da sunucu yanıt vermiyor. Yazdıklarınız gönderilmedi. Sunucuda komut orada sürebilir; Enterm bunu bilemez.")
            }
            .padding(20)
            DialogButtons {
                Btn("Kapat", kind: .plain, key: "Esc") { model.overlay = nil }
                Btn("Yeniden Bağlan", kind: .primary, key: "⏎") {
                        model.overlay = nil
                        model.close(number)
                        remote?.open()
                    }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 560)
    }
}

// MARK: Run configurations

struct RunPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @State private var configs: [RunConfig] = []
    @State private var pendingConfirm: RunConfig?
    private var folder: String { model.focusedInfo?.cwd ?? NSHomeDirectory() }
    private func session(_ config: RunConfig) -> SessionInfo? {
        model.sessions.first { $0.name == "çalıştır: \(config.name)" }
    }
    var body: some View {
        PageFrame(title: "Çalıştır") {
            Dim(model.displayPath(folder)).lineLimit(1).truncationMode(.head)
            if configs.isEmpty {
                Dim("Bu klasörde .vscode/launch.json ya da package.json betiği bulunamadı.")
            } else {
                Panel {
                    ForEach(configs) { config in
                        if config.id != configs.first?.id { Line() }
                        Row {
                            VStack(alignment: .leading, spacing: 2) {
                                T(config.name, bold: true)
                                Dim("\(config.command) · \(config.source)").lineLimit(1)
                            }
                            Spacer()
                            if let info = session(config) {
                                Dim("● Çalışıyor")
                                // A pair of buttons sits 8 apart, not at the row's 24.
                                HStack(spacing: 8) {
                                    Btn("Tarayıcıda Aç", kind: .plain) { openInBrowser(info) }
                                    Btn("Durdur", kind: .plain) { model.close(info.number) }
                                }
                            } else {
                                Dim("○ Durdu")
                                Btn("Başlat") { start(config) }
                            }
                        }
                    }
                }
            }
            if let config = pendingConfirm {
                Panel(border: Theme.palette.need) {
                    VStack(alignment: .leading, spacing: 8) {
                        T("Depodaki Bu Komut İlk Kez Çalışacak", bold: true)
                        Mono(config.command).textSelection(.enabled)
                        HStack {
                            Btn("Vazgeç", kind: .plain) { pendingConfirm = nil }
                            Btn("Çalıştır", kind: .primary) {
                                RunTrust.accept(folder: folder, config: config)
                                pendingConfirm = nil
                                launch(config)
                            }
                        }
                    }
                    .padding(12)
                }
            }
            Dim("Komut bu bilgisayarda çalışır. Depoda yeni bir komut görülürse ilk çalıştırmada sorulur.")
        }
        .onAppear { configs = RunConfig.load(folder: folder) }
    }
    private func start(_ config: RunConfig) {
        if RunTrust.isAccepted(folder: folder, config: config) {
            launch(config)
        } else {
            pendingConfirm = config
        }
    }
    private func launch(_ config: RunConfig) {
        var spec = SessionSpec(name: "çalıştır: \(config.name)", tool: .terminal, cwd: folder, rows: 30, cols: 100)
        spec.env = ["ENTERM_STARTUP": config.command]
        model.create(spec)
    }
    private func openInBrowser(_ info: SessionInfo) {
        var tail = WireMessage(op: "tail")
        tail.number = info.number
        model.connection.request(tail) { reply in
            let text = reply.text ?? ""
            let range = text.range(of: "https?://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?[^\\s]*", options: .regularExpression)
            BrowserCenter.shared.load(range.map { String(text[$0]) } ?? "http://localhost:3000")
            AppModel.shared.page = .browser
        }
    }
}

enum RunTrust {
    private static var file: URL { EntermPaths.support.appendingPathComponent("run-trust.json") }
    private static func key(_ folder: String, _ config: RunConfig) -> String { folder + "|" + config.command }
    static func isAccepted(folder: String, config: RunConfig) -> Bool {
        (JSONStore.load([String].self, from: file) ?? []).contains(key(folder, config))
    }
    static func accept(folder: String, config: RunConfig) {
        var list = JSONStore.load([String].self, from: file) ?? []
        list.append(key(folder, config))
        JSONStore.save(list, to: file)
    }
}

// MARK: Whiteboard

struct BoardShape: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case pen, box, arrow, text }
    var id = UUID()
    var kind: Kind
    var points: [CGPoint]
    var text = ""
}

struct WhiteboardPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @Environment(\.boxedPage) private var boxed
    @State private var shapes: [BoardShape] = []
    @State private var current: BoardShape?
    @State private var tool = BoardShape.Kind.pen
    @State private var label = ""
    @State private var status = ""
    private var folder: String { model.focusedInfo?.cwd ?? NSHomeDirectory() }
    private var dataURL: URL { URL(fileURLWithPath: folder).appendingPathComponent(".enterm/tahta/tahta.json") }
    var body: some View {
        PageFrame(title: nil, wide: true) {
            HStack {
                T("Beyaz Tahta", bold: true)
                Spacer()
                Seg(options: [(BoardShape.Kind.pen, "Kalem"), (.box, "Kutu"), (.arrow, "Ok"), (.text, "Yazı")], value: $tool)
                if tool == .text { EntermField(placeholder: "Yazı, Sonra Tıklayın", text: $label).frame(width: 200) }
                Btn("Geri Al", kind: .plain) {
                    if !shapes.isEmpty { shapes.removeLast() }
                    save()
                }
                Btn("Ajana Göster", kind: .primary) { show() }
            }
            canvas
                .frame(minHeight: boxed ? 120 : 520)
                .background(Color(Theme.palette.panel))
                .cornerRadius(Theme.cornerCard)
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).stroke(Color(Theme.palette.hair)))
                .overlay(MouseCatcher(changed: { dragged($0) }, ended: { ended() }))
            Dim("Dosya: .enterm/tahta/tahta.json. Kapalıyken yük yok. \(status)")
        }
        .onAppear(perform: load)
    }
    private var canvas: some View {
        Canvas { context, _ in
            for shape in shapes + (current.map { [$0] } ?? []) { Self.draw(shape, in: &context) }
        }
    }
    static func draw(_ shape: BoardShape, in context: inout GraphicsContext) {
        let color = Color(Theme.palette.fg)
        guard let first = shape.points.first else { return }
        let last = shape.points.last ?? first
        var path = Path()
        switch shape.kind {
        case .pen:
            path.addLines(shape.points)
        case .box:
            path.addRoundedRect(in: CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y)), cornerSize: CGSize(width: 6, height: 6))
        case .arrow:
            path.move(to: first)
            path.addLine(to: last)
            let angle = atan2(last.y - first.y, last.x - first.x)
            for side in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                path.move(to: last)
                path.addLine(to: CGPoint(x: last.x + 12 * cos(angle + side), y: last.y + 12 * sin(angle + side)))
            }
        case .text:
            context.draw(Text(shape.text).font(Theme.swiftFont()).foregroundColor(color), at: first, anchor: .topLeading)
            return
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }
    private func dragged(_ location: CGPoint) {
        if current == nil {
            current = BoardShape(kind: tool, points: [location], text: tool == .text ? label : "")
        } else if tool == .pen {
            current?.points.append(location)
        } else {
            current?.points = [current?.points.first ?? location, location]
        }
    }
    private func ended() {
        if let current, current.kind != .text || !current.text.isEmpty { shapes.append(current) }
        current = nil
        save()
    }
    private func load() {
        if let data = try? Data(contentsOf: dataURL), let list = try? JSONDecoder().decode([BoardShape].self, from: data) { shapes = list }
    }
    private func save() {
        try? FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(shapes) { try? data.write(to: dataURL, options: .atomic) }
    }
    /// Saves a picture and writes its path into the focused session's prompt. The user presses Enter.
    @MainActor private func show() {
        let list = shapes
        let renderer = ImageRenderer(content: Canvas { context, _ in
            for shape in list { Self.draw(shape, in: &context) }
        }
        .frame(width: 1200, height: 800)
        .background(Color(Theme.palette.panel)))
        let file = dataURL.deletingLastPathComponent().appendingPathComponent("tahta.png")
        guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              (try? png.write(to: file)) != nil else {
            status = "Görüntü Kaydedilemedi."
            return
        }
        if let number = model.focused {
            model.connection.sendInput(number: number, bytes: Data(file.path.utf8))
        }
        model.page = nil
    }
}

// MARK: Simulator

/// Shows a booted simulator's screen. Only while this page is open, and only when the picture changed.
final class SimulatorFeed: ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let booted: Bool
    }
    @Published var devices: [Device] = []
    @Published var image: NSImage?
    @Published var note = ""
    private var timer: Timer?
    private var lastData: Data?
    private var busy = false

    private static func simctl(_ arguments: [String]) -> (ok: Bool, data: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return (false, Data()) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0, data)
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.simctl(["list", "devices", "available", "-j"])
            var list: [Device] = []
            if result.ok, let object = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any], let groups = object["devices"] as? [String: [[String: Any]]] {
                for (runtime, items) in groups where runtime.contains("iOS") {
                    for item in items {
                        guard let id = item["udid"] as? String, let name = item["name"] as? String else { continue }
                        list.append(Device(id: id, name: name, booted: item["state"] as? String == "Booted"))
                    }
                }
            }
            DispatchQueue.main.async {
                self?.devices = list.sorted { ($0.booted ? 0 : 1, $0.name) < ($1.booted ? 0 : 1, $1.name) }
                self?.note = result.ok ? "" : "simctl çalışmadı. Xcode gerekir."
            }
        }
    }

    func boot(_ device: Device) {
        note = "\(device.name) Açılıyor"
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = Self.simctl(["boot", device.id])
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func startFeed(_ device: Device) {
        stopFeed()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.capture(device) }
        timer.tolerance = 0.5
        self.timer = timer
        capture(device)
    }

    private func capture(_ device: Device) {
        guard !busy else { return }
        busy = true
        let file = NSTemporaryDirectory() + "enterm-sim-\(device.id).png"
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = Self.simctl(["io", device.id, "screenshot", "--type=png", file])
            let data = try? Data(contentsOf: URL(fileURLWithPath: file))
            try? FileManager.default.removeItem(atPath: file)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if let data, data != self.lastData {
                    self.lastData = data
                    self.image = NSImage(data: data)
                }
            }
        }
    }

    func stopFeed() {
        timer?.invalidate()
        timer = nil
        image = nil
        lastData = nil
    }
}

struct SimulatorPage: View {
    @StateObject private var feed = SimulatorFeed()
    @State private var selected: SimulatorFeed.Device?
    var body: some View {
        PageFrame(title: "iOS Simülatörü", wide: true) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    if !feed.note.isEmpty { Dim(feed.note) }
                    Panel {
                        ScrollView {
                            MenuList {
                                ForEach(feed.devices) { device in
                                    MenuRow(title: device.name, note: device.booted ? "● Açık" : "○ Kapalı", selected: selected == device) {
                                        selected = device
                                        if device.booted { feed.startFeed(device) }
                                    }
                                }
                            }
                        }
                        .frame(height: 420)
                    }
                    if let device = selected, !device.booted {
                        Btn("\(device.name) Başlat", kind: .primary) { feed.boot(device) }
                        Dim("Simülatör belleği çok kullanır. Yalnız isterseniz başlatın.")
                    }
                    Btn("Simulator Uygulamasını Aç", kind: .plain) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"))
                    }
                    Dim("Yalnız açıkken akar. Ekran değişmezse görüntü yenilenmez. Dokunma ve ajanın kullanması bu sürümde yok, Simulator uygulamasından yapılır.")
                }
                .frame(width: 320)
                if let image = feed.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 620).cornerRadius(6)
                } else {
                    Dim("Açık bir cihaz seçin.")
                }
            }
        }
        .onAppear { feed.refresh() }
        .onDisappear { feed.stopFeed() }
    }
}

// MARK: Uninstall

enum Uninstaller {
    private static var file: URL { EntermPaths.support.appendingPathComponent("written-files.json") }
    static func remember(hookFile: String) {
        var list = JSONStore.load([String].self, from: file) ?? []
        if !list.contains(hookFile) { list.append(hookFile) }
        JSONStore.save(list, to: file)
    }
    static func hookFiles() -> [String] { JSONStore.load([String].self, from: file) ?? [] }

    /// Removes Enterm's own data only. Conversations, logins and folders of the official programs stay.
    static func removeEverything() {
        let model = AppModel.shared
        for account in AccountStore.shared.accounts where account.kind == .apiKey { Keychain.delete(account: account.id) }
        for path in hookFiles() { try? FileManager.default.removeItem(atPath: path) }
        model.connection.send(WireMessage(op: "shutdown"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            try? FileManager.default.removeItem(at: EntermPaths.support)
            NSApp.terminate(nil)
        }
    }
}

struct UninstallPage: View {
    @ObservedObject var model = AppModel.shared
    @State private var confirm = false
    var body: some View {
        PageFrame(title: "Enterm'i Kaldır", centered: true) {
            T("Silinecekler", bold: true)
            VStack(alignment: .leading, spacing: 4) {
                Dim(model.displayPath(EntermPaths.support.path) + ": ayarlar, hesap dizinleri, dökümler, pano, ekip, mesajlar")
                Dim("Anahtar Zinciri: Enterm'e eklenen API anahtarları")
                ForEach(Uninstaller.hookFiles(), id: \.self) { Dim($0) }
                Dim("\(model.sessions.count) açık oturum kapanır, çalışan iş durur.")
            }
            T("Kalanlar", bold: true)
            Dim("~/.claude, ~/.codex ve ~/.gemini'ye Enterm yazmaz, dokunulmaz. Projelerdeki ekip/ ve .enterm/ klasörleri sizindir, kalır. Enterm.app dosyasını sonra Çöp Sepeti'ne taşıyın.")
            if confirm {
                HStack {
                    Btn("Vazgeç", kind: .plain) { confirm = false }
                    Btn("Evet, Hepsini Sil Ve Kapat", kind: .danger) { Uninstaller.removeEverything() }
                }
            } else {
                Btn("Kaldır", kind: .danger) { confirm = true }
            }
        }
    }
}

/// Mouse tracking from AppKit, so drawing inside a scrolling page does not turn into scrolling.
struct MouseCatcher: NSViewRepresentable {
    let changed: (CGPoint) -> Void
    let ended: () -> Void
    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) {
        view.changed = changed
        view.ended = ended
    }
    final class CatcherView: NSView {
        var changed: ((CGPoint) -> Void)?
        var ended: (() -> Void)?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { changed?(convert(event.locationInWindow, from: nil)) }
        override func mouseDragged(with event: NSEvent) { changed?(convert(event.locationInWindow, from: nil)) }
        override func mouseUp(with event: NSEvent) { ended?() }
    }
}
