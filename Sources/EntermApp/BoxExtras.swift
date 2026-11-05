import AVKit
import EntermCore
import SwiftUI
import WebKit

// Small views for the canvas. Each one exists only while its box is open.

/// A page in its own box, for a design or a local preview. Agents have their own browser, this one is yours.
struct WebBox: View {
    let item: CanvasItem
    @State private var address = ""
    @State private var loaded = ""
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                EntermField(placeholder: "Adres ya da dosya yolu", text: $address)
                    .onSubmit(go)
                Btn("Git", kind: .plain) { go() }
                if !loaded.isEmpty, !loaded.hasPrefix("/"), !loaded.hasPrefix("~") {
                    IconBtn("safari", label: "Safari'de Aç") { BrowserCenter.openInSafari(loaded) }.help("Safari'de Aç")
                }
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 8))
            if loaded.isEmpty {
                Spacer()
                Dim("Bir adres yazın, Enter'a basın")
                Spacer()
            } else {
                WebBoxView(address: loaded)
            }
        }
        .onAppear {
            address = item.text
            loaded = item.text
        }
    }

    private func go() {
        var text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if !text.contains("://"), !text.hasPrefix("/"), !text.hasPrefix("~") { text = (text.hasPrefix("localhost") ? "http://" : "https://") + text }
        address = text
        loaded = text
        AppModel.shared.updateItem(item.id, text: text)
    }
}

private struct WebBoxView: NSViewRepresentable {
    let address: String
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = SettingsStore.shared.settings.browserKeepLogins ? .default() : .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        load(view)
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.last != address {
            context.coordinator.last = address
            load(view)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(last: address) }
    final class Coordinator {
        var last: String
        init(last: String) { self.last = last }
    }
    private func load(_ view: WKWebView) {
        if address.hasPrefix("/") || address.hasPrefix("~") {
            let url = URL(fileURLWithPath: (address as NSString).expandingTildeInPath)
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if let url = URL(string: address) {
            view.load(URLRequest(url: url))
        }
    }
}

/// A video file. It plays when you press play, and stops costing anything when paused.
struct VideoBox: View {
    let item: CanvasItem
    @State private var player: AVPlayer?
    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                VStack(spacing: 8) {
                    Dim("Bir video seçin")
                    Btn("Dosya Seç") { choose() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if !item.text.isEmpty { player = AVPlayer(url: URL(fileURLWithPath: item.text)) }
        }
        .onDisappear { player?.pause() }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.prompt = "Seç"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppModel.shared.updateItem(item.id, text: url.path)
        player = AVPlayer(url: url)
    }
}

/// A short game for the wait. The enter key jumps over the lines coming at it. It draws only while you play.
struct RunnerGame: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @State private var playing = false
    @State private var y: CGFloat = 0
    @State private var velocity: CGFloat = 0
    @State private var obstacles: [CGFloat] = []
    @State private var score = 0
    @State private var best = 0
    @State private var last = Date()
    @State private var over = false

    var body: some View {
        let palette = Theme.palette
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if playing {
                    TimelineView(.animation) { context in
                        Canvas { graphics, size in
                            draw(&graphics, size: size)
                        }
                        .onChange(of: context.date) { date in step(date, width: geometry.size.width) }
                    }
                } else {
                    Canvas { graphics, size in draw(&graphics, size: size) }
                }
                HStack {
                    T("\(score)", color: palette.need, weight: .semibold)
                    Spacer()
                    Dim("En İyi \(best)")
                }
                .padding(12)
                if !playing {
                    VStack(spacing: 8) {
                        T(over ? "Oyun Bitti" : "Enter Koşusu", bold: true, style: .section)
                        Dim("Tıklayın, zıplayın")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { tap(width: geometry.size.width) }
        }
    }

    private func draw(_ graphics: inout GraphicsContext, size: CGSize) {
        let palette = Theme.palette
        let ground = size.height - 28
        var line = Path()
        line.move(to: CGPoint(x: 0, y: ground))
        line.addLine(to: CGPoint(x: size.width, y: ground))
        graphics.stroke(line, with: .color(Color(palette.hair2)), lineWidth: 1)
        // The hero is the key itself: a block with the arrow on it.
        let hero = CGRect(x: 36, y: ground - 24 - y, width: 24, height: 24)
        graphics.fill(Path(roundedRect: hero, cornerRadius: 4), with: .color(Color(palette.need)))
        var arrow = Path()
        arrow.move(to: CGPoint(x: hero.maxX - 6, y: hero.minY + 6))
        arrow.addLine(to: CGPoint(x: hero.maxX - 6, y: hero.midY + 3))
        arrow.addLine(to: CGPoint(x: hero.minX + 6, y: hero.midY + 3))
        arrow.move(to: CGPoint(x: hero.minX + 10, y: hero.midY - 1))
        arrow.addLine(to: CGPoint(x: hero.minX + 6, y: hero.midY + 3))
        arrow.addLine(to: CGPoint(x: hero.minX + 10, y: hero.midY + 7))
        graphics.stroke(arrow, with: .color(Color(palette.btnfg)), lineWidth: 1.5)
        for x in obstacles {
            graphics.fill(Path(CGRect(x: x, y: ground - 22, width: 4, height: 22)), with: .color(Color(palette.g1)))
        }
    }

    private func tap(width: CGFloat) {
        if !playing {
            playing = true
            over = false
            y = 0
            velocity = 0
            score = 0
            obstacles = [width + 40]
            last = Date()
        } else if y == 0 {
            velocity = 420
        }
    }

    private func step(_ date: Date, width: CGFloat) {
        let delta = CGFloat(min(date.timeIntervalSince(last), 0.05))
        last = date
        y = max(0, y + velocity * delta)
        velocity = y == 0 ? 0 : velocity - 1100 * delta
        let speed = 180 + CGFloat(score) * 4
        obstacles = obstacles.map { $0 - speed * delta }
        if let first = obstacles.first, first < -10 {
            obstacles.removeFirst()
            score += 1
            best = max(best, score)
        }
        if (obstacles.last ?? 0) < width - CGFloat.random(in: 180...320) { obstacles.append(width + 10) }
        if obstacles.contains(where: { $0 > 32 && $0 < 60 }) && y < 22 {
            playing = false
            over = true
        }
    }
}
