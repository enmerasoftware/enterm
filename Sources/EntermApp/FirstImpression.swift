import AppKit
import EntermCore
import SwiftUI

// The first impression: welcome, tour, home, the session rail and the command bar.
// Measures live in tasarim/kabuk-olculeri.md, Bölüm 13. Motion runs only when something happens.

enum Neon {
    private static var setting: String { SettingsStore.shared.settings.neon }
    static var on: Bool { setting != "off" && !PowerCenter.shared.settings.lowPower }
    static var opacity: Float { on ? (setting == "strong" ? 1 : 0.85) : 0 }
    static var radius: CGFloat { setting == "strong" ? 9 : 4 }

    /// A plain terminal has nothing to report: it is always "running" and never lit.
    static func color(_ info: SessionInfo) -> NSColor? {
        info.tool == .terminal ? nil : color(info.status)
    }

    /// The colour says what is happening. A box with nothing to say has no light.
    static func color(_ status: SessionStatus) -> NSColor? {
        let palette = Theme.palette
        switch status {
        case .running: return palette.g1
        case .needsApproval: return palette.need
        case .limitReached: return palette.limit
        case .failed, .notFound: return palette.err
        default: return nil
        }
    }
}

enum Motion {
    static var allowed: Bool {
        MotionPolicy.allowed(setting: SettingsStore.shared.settings.motion,
                             reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                             lowPower: PowerCenter.shared.settings.lowPower,
                             windowVisible: AppModel.shared.windowVisible)
    }
}

extension View {
    /// A soft light. Static, and gone when the neon setting is off.
    func neon(_ color: NSColor, radius: CGFloat = 8) -> some View {
        shadow(color: Neon.on ? Color(color).opacity(0.7) : .clear, radius: radius)
    }
}

/// Two faint lights in opposite corners, and nothing else on the ground.
struct CornerGlows: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    var first: UnitPoint = .topTrailing
    var second: UnitPoint = .bottomLeading
    var body: some View {
        let palette = Theme.palette
        ZStack {
            RadialGradient(colors: [Color(palette.need).opacity(Theme.isLight ? 0.10 : 0.14), .clear], center: first, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(palette.g1).opacity(Theme.isLight ? 0.10 : 0.15), .clear], center: second, startRadius: 0, endRadius: 480)
        }
        .opacity(Neon.on ? 1 : 0)
        .allowsHitTesting(false)
    }
}

/// The main action everywhere: the title and the key that does the same thing.
private struct EnterButton: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let title: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text("⏎")
                    .font(.system(size: 15))
                    .foregroundColor(Color(palette.btn))
                    // 24 in a 44 button: 10 above, below and to the right.
                    .frame(width: 24, height: 24)
                    .background(Color(palette.btnfg))
                    .cornerRadius(Theme.cornerControl)
            }
            .foregroundColor(Color(palette.btnfg))
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(height: 44)
            .background(Color(palette.btn).brightness(hovering ? 0.06 : 0))
            .cornerRadius(Theme.cornerCard)
            .neon(palette.btn, radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .keyboardShortcut(.return, modifiers: [])
        .onHover { hovering = $0 }
    }
}

private struct QuietButton: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let title: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Color(Theme.palette.text1))
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(hovering ? Color(Theme.palette.fill) : .clear)
                .cornerRadius(Theme.cornerCard)
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).stroke(Color(Theme.palette.hair2)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}

private struct BlinkingCursor: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let width: CGFloat
    let height: CGFloat
    @State private var dim = false
    var body: some View {
        Rectangle()
            .fill(Color(Theme.palette.need))
            .frame(width: width, height: height)
            .cornerRadius(2)
            .neon(Theme.palette.need, radius: width)
            .opacity(dim ? 0.25 : 1)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 550_000_000)
                    if Motion.allowed { dim.toggle() } else { dim = false }
                }
            }
    }
}

// MARK: Welcome

/// The Enter line: down from the top, one turn, then left to the cursor.
private struct EnterLine: Shape {
    let endX: CGFloat
    let downX: CGFloat
    let y: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: downX, y: -10))
        path.addLine(to: CGPoint(x: downX, y: y - 32))
        path.addQuadCurve(to: CGPoint(x: downX - 32, y: y), control: CGPoint(x: downX, y: y))
        path.addLine(to: CGPoint(x: endX, y: y))
        return path
    }
}

private struct WelcomeCover: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let begin: () -> Void
    let finish: () -> Void
    @State private var drawn = false
    @State private var comet: CGFloat = -0.1
    @State private var showComet = false

    var body: some View {
        let palette = Theme.palette
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            let wide = width >= 1000
            let y = (height * 0.41).rounded()
            let endX: CGFloat = 392
            let downX = width - 160
            ZStack(alignment: .topLeading) {
                if wide {
                    let line = EnterLine(endX: endX, downX: downX, y: y)
                    line.trim(from: 0, to: drawn ? 1 : 0)
                        .stroke(Color(palette.need), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .neon(palette.need, radius: 5)
                    if showComet {
                        line.trim(from: max(0, comet), to: min(1, comet + 0.07))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    Path { path in
                        path.move(to: CGPoint(x: endX + 16, y: y - 14))
                        path.addLine(to: CGPoint(x: endX, y: y))
                        path.addLine(to: CGPoint(x: endX + 16, y: y + 14))
                    }
                    .stroke(Color(palette.need), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .opacity(drawn ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(1.2), value: drawn)
                    station("Claude Code", state: "Çalışıyor", color: palette.g1, x: downX, y: height * 0.12, delay: 0.35)
                    station("Codex", state: "Sıra Sizde", color: palette.need, x: downX, y: height * 0.25, delay: 0.55)
                    Circle()
                        .fill(Color(palette.terminal))
                        .overlay(Circle().stroke(Color(palette.add), lineWidth: 2))
                        .frame(width: 12, height: 12)
                        .neon(palette.add)
                        .position(x: width * 0.62, y: y)
                        .opacity(drawn ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.95), value: drawn)
                    HStack(spacing: 8) {
                        Text("Bitti").font(.system(size: 12)).foregroundColor(Color(palette.add))
                        Text("Antigravity").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(palette.text1))
                    }
                    .fixedSize()
                    .position(x: width * 0.62, y: y - 24)
                    .rise(drawn, delay: 0.95)
                }
                HStack(spacing: 10) {
                    Text("enterm")
                        .font(Theme.swiftFont(bold: true, size: 68))
                        .tracking(-2.5)
                        .foregroundColor(Color(palette.text1))
                    BlinkingCursor(width: 26, height: 60)
                }
                .frame(height: 84)
                .position(x: 96 + 133, y: y)
                VStack(alignment: .leading, spacing: 24) {
                    Text("Bütün terminalleriniz, tek masada.")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color(palette.text1))
                    HStack(spacing: 12) {
                        EnterButton(title: "Bir Dakikada Kur", action: begin)
                        QuietButton(title: "Doğrudan Terminali Aç") {
                            finish()
                            // With sessions open from before, the canvas is what they came back to.
                            if AppModel.shared.sessions.isEmpty { AppModel.shared.newTerminal() }
                        }
                    }
                }
                .padding(.leading, 96)
                .padding(.top, y + 56)
                .rise(drawn, delay: 0.7)
                if height >= 640 {
                    HStack(alignment: .top, spacing: 32) {
                        point("Bilgisayarınızı yormaz", "Yerel Mac uygulamasıdır. Kullanmadığınız özellik çalışmaz.", palette.add, delay: 1)
                        point("Kapatsanız da sürer", "Oturumlar arkada çalışır, döndüğünüzde kaldığı yerde durur.", palette.need, delay: 1.1)
                        point("Resmi programlar, olduğu gibi", "Claude Code, Codex, Antigravity. Kendi ayarlarınıza dokunulmaz.", palette.g1, delay: 1.2)
                        point("İşinizi önünüze serin", "Terminalleri taşıyın, birbirine bağlayın, yakınlaştırın.", palette.g2, delay: 1.3)
                    }
                    .padding(.horizontal, 96)
                    .frame(width: width, height: height - 44, alignment: .bottom)
                }
                // Where every page's back button stands: 80 in, centred in the same 44 band.
                Btn("Atla", kind: .plain, action: finish)
                    .padding(.leading, 80)
                    .padding(.top, 7)
            }
        }
        .onAppear {
            guard Motion.allowed else { drawn = true; return }
            withAnimation(.timingCurve(0.6, 0, 0.2, 1, duration: 1.3)) { drawn = true }
        }
        .task {
            // A light passes along the line now and then, only on this screen.
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            while !Task.isCancelled, Motion.allowed {
                comet = -0.1
                showComet = true
                withAnimation(.linear(duration: 1.4)) { comet = 1 }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                showComet = false
                try? await Task.sleep(nanoseconds: 4_500_000_000)
            }
        }
    }

    private func station(_ name: String, state: String, color: NSColor, x: CGFloat, y: CGFloat, delay: Double) -> some View {
        HStack(spacing: 8) {
            Text(state).font(.system(size: 12)).foregroundColor(Color(color))
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundColor(Color(Theme.palette.text1))
            Circle()
                .fill(Color(Theme.palette.terminal))
                .overlay(Circle().stroke(Color(color), lineWidth: 2))
                .frame(width: 12, height: 12)
                .neon(color)
        }
        .frame(width: 260, alignment: .trailing)
        .position(x: x - 124, y: y)
        .rise(drawn, delay: delay)
    }

    private func point(_ title: String, _ detail: String, _ color: NSColor, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Color(color).opacity(0.65)).frame(height: 1).padding(.bottom, 8)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Color(Theme.palette.text1))
            Text(detail).font(.system(size: 13)).foregroundColor(Color(Theme.palette.text2)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rise(drawn, delay: delay)
    }
}

private extension View {
    func rise(_ shown: Bool, delay: Double) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .animation(Motion.allowed ? .easeOut(duration: 0.4).delay(delay) : nil, value: shown)
    }
}

enum TourStep: Int, CaseIterable {
    case program, voice, views, chat, notify, awake, notch, keys, phone

    var short: String {
        switch self {
        case .program: return "Program"
        case .voice: return "Ses"
        case .views: return "Görünüm"
        case .chat: return "Sohbet"
        case .notify: return "Bildirim"
        case .awake: return "Uyanık"
        case .notch: return "Çentik"
        case .keys: return "Kısayol"
        case .phone: return "Telefon"
        }
    }
    var title: String {
        switch self {
        case .program: return "Neyle başlayalım?"
        case .voice: return "Konuşarak yazın"
        case .views: return "Tek proje, iki görünüm"
        case .chat: return "Sohbet gibi okuyun"
        case .notch: return "Çentikte tek bakış"
        case .notify: return "Sizi beklerken haber versin"
        case .awake: return "Uzun işler yarım kalmasın"
        case .keys: return "Birkaç tuş yeter"
        case .phone: return "Oturumlar cebinizde"
        }
    }
    var detail: String {
        switch self {
        case .program: return "Ana ekranda Enter'a basınca hangi program açılsın? Düz terminal de tamamen yeterli, sonra değişir."
        case .voice: return "⌃⌘ tuşlarını basılı tutun, konuşun, bırakın, yazıya dönsün. Metni siz gönderirsiniz."
        case .views: return "İşinizi terminal masası ya da yapılacaklar panosu olarak görün. Pano kartları canlı oturumlardır."
        case .chat: return "Claude Code ve Codex oturumu tek tuşla konuşmaya döner. Yanıtı alttan yazar, onayı buradan verirsiniz. Aynı tuşla terminale dönersiniz."
        case .notch: return "Hangi oturum çalışıyor, hangisi sizi bekliyor, MacBook çentiğinde görün. Üzerine gelince küçük liste açılır."
        case .notify: return "Bir program işini bitirince ya da onay isteyince başka işteyken de görün."
        case .awake: return "Bir program çalışırken Mac uyumaz, iş bitince bu izni hemen bırakır. Kapak kapanırsa Mac yine uyur."
        case .keys: return "Her işin bir kısayolu var, hepsini Ayarlar'dan değiştirebilirsiniz."
        case .phone: return "iPhone ile QR kodu okutun, aynı oturumları izleyin, onay verin, yazın. Bağlantı uçtan uca şifrelidir."
        }
    }
}

private struct TourView: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var catalog = ToolCatalog.shared
    @ObservedObject var whisper = WhisperCenter.shared
    @State private var step = TourStep.program
    @State private var movedForward = true
    let finish: () -> Void

    var body: some View {
        let palette = Theme.palette
        GeometryReader { geometry in
            let wide = geometry.size.width >= 1000
            HStack(alignment: .top, spacing: 0) {
                rail.frame(width: 150).padding(.leading, 56)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(step.rawValue + 1) / \(TourStep.allCases.count)")
                        .font(Theme.swiftFont(size: 12))
                        .foregroundColor(Color(palette.need))
                    Text(step.title)
                        .font(.system(size: 34, weight: .semibold))
                        .tracking(-0.6)
                        .foregroundColor(Color(palette.text1))
                        .padding(.top, 10)
                    Text(step.detail)
                        .font(.system(size: 15))
                        .lineSpacing(5)
                        .foregroundColor(Color(palette.text2))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                    choices.padding(.top, 20)
                    Spacer(minLength: 16)
                    HStack(spacing: 10) {
                        EnterButton(title: step == .phone ? "Başla" : "Devam") { next() }
                        if step != .program {
                            QuietButton(title: "Geri") { go(TourStep(rawValue: step.rawValue - 1) ?? .program) }
                        }
                    }
                }
                .frame(width: 420, alignment: .leading)
                .frame(maxHeight: 520)
                .padding(.leading, 42)
                if wide {
                    scene
                        .frame(maxWidth: .infinity, maxHeight: 520)
                        .padding(.horizontal, 48)
                        .id(step)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: movedForward ? 12 : -12)), removal: .opacity))
                }
            }
            .padding(.top, max(56, (geometry.size.height - 520) / 2))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topLeading) {
            Btn("Atla", kind: .plain, action: finish)
                .padding(.leading, 80)
                .padding(.top, 7)
        }
    }

    private func next() {
        if let following = TourStep(rawValue: step.rawValue + 1) { go(following) } else { finish() }
    }

    private func go(_ target: TourStep) {
        movedForward = target.rawValue > step.rawValue
        if Motion.allowed {
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.32)) { step = target }
        } else {
            step = target
        }
    }

    private var rail: some View {
        let palette = Theme.palette
        let spacing: CGFloat = 36
        let all = TourStep.allCases
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(palette.hair2)).frame(width: 2, height: spacing * CGFloat(all.count - 1)).padding(.leading, 5).padding(.top, 18)
            Rectangle().fill(Color(palette.need)).frame(width: 2, height: spacing * CGFloat(step.rawValue)).neon(palette.need, radius: 3).padding(.leading, 5).padding(.top, 18)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(all, id: \.rawValue) { item in
                    TourRailItem(title: item.short, done: item.rawValue <= step.rawValue, here: item == step, height: spacing) { go(item) }
                }
            }
        }
    }

    @ViewBuilder
    private var choices: some View {
        switch step {
        case .program:
            VStack(spacing: 0) {
                option("Düz Terminal", note: "", on: store.settings.defaultProgram == "terminal") { store.settings.defaultProgram = "terminal" }
                programOption(.claude, id: "claude")
                programOption(.codex, id: "codex")
                programOption(.antigravity, id: "agy")
            }
        case .voice:
            VStack(spacing: 0) {
                option("Mac'in Diktesi", note: "İndirme yok", on: store.settings.voiceEnabled && store.settings.voiceEngine == "system") {
                    store.settings.voiceEnabled = true
                    store.settings.voiceEngine = "system"
                }
                option("Yerel Whisper", note: whisperNote, on: store.settings.voiceEnabled && store.settings.voiceEngine == "whisper") {
                    store.settings.voiceEnabled = true
                    store.settings.voiceEngine = "whisper"
                    if let tiny = WhisperCenter.models.first, !WhisperCenter.shared.isReady(tiny) { WhisperCenter.shared.download(tiny) }
                }
                option("Kapalı", note: "", on: !store.settings.voiceEnabled) { store.settings.voiceEnabled = false }
            }
        case .views:
            VStack(alignment: .leading, spacing: 0) {
                option("Masa Görünümü", note: "", on: !store.settings.defaultBoardView) { store.settings.defaultBoardView = false }
                option("Pano Görünümü", note: "", on: store.settings.defaultBoardView) { store.settings.defaultBoardView = true }
                Dim("Geçmek için: ⌘⇧B").padding(.top, 12)
            }
        case .chat:
            Dim("Denemek için: bir Claude Code oturumunda ⌘⇧M")
        case .notch:
            VStack(spacing: 0) {
                option("Çentikte Göster", note: "", on: store.settings.notch) { store.settings.notch = true; NotchCenter.shared.update() }
                option("Gösterme", note: "", on: !store.settings.notch) { store.settings.notch = false; NotchCenter.shared.update() }
            }
        case .notify:
            VStack(spacing: 0) {
                option("Bildirimleri Aç", note: "macOS izni sorulur", on: store.settings.systemNotifications) { store.settings.systemNotifications = true }
                option("Şimdilik Kapalı", note: "", on: !store.settings.systemNotifications) { store.settings.systemNotifications = false }
            }
        case .awake:
            VStack(spacing: 0) {
                option("Çalışırken Uyanık Tut", note: "Önerilen", on: store.settings.keepAwakeWhileAgents) { store.settings.keepAwakeWhileAgents = true }
                option("Mac Kendi Bilsin", note: "", on: !store.settings.keepAwakeWhileAgents) { store.settings.keepAwakeWhileAgents = false }
            }
        case .keys:
            VStack(spacing: 0) {
                keyRow("Her Şeyi Bul", "⌘K")
                keyRow("Yeni Terminal", "⌘T")
                keyRow("Tam Ekran", "⌘⏎")
                keyRow("Onay Kutusu", "⌘⇧O")
            }
        case .phone:
            TourLink(title: "Şimdi Eşleştir") {
                finish()
                Commands.perform("phone")
            }
        }
    }

    private var whisperNote: String {
        if whisper.downloading != nil { return "İndiriliyor %\(Int(whisper.progress * 100))" }
        if whisper.chosen != nil { return "Hazır" }
        return whisper.program == nil ? "whisper-cli Gerekli" : "75 MB İner"
    }

    private func programOption(_ tool: ToolKind, id: String) -> some View {
        let missing = catalog.isMissing(tool)
        return option(tool.title, note: missing ? "Kurulu Değil" : "Bulundu", on: store.settings.defaultProgram == id) { store.settings.defaultProgram = id }
    }

    private func option(_ title: String, note: String, on: Bool, action: @escaping () -> Void) -> some View {
        TourOption(title: title, note: note, on: on, action: action)
    }

    private func keyRow(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title).font(.system(size: 14)).foregroundColor(Color(Theme.palette.text1))
            Spacer()
            Key(key)
        }
        // The same height as a choice row: both lists stand in the same spot.
        .frame(height: TourOption.height)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(Theme.palette.hair)).frame(height: 1) }
    }

    @ViewBuilder
    private var scene: some View {
        let palette = Theme.palette
        switch step {
        case .program:
            let program = store.settings.defaultProgram
            let tool: ToolKind = program == "claude" ? .claude : program == "codex" ? .codex : program == "agy" ? .antigravity : .terminal
            let color: NSColor = tool == .claude ? palette.g1 : tool == .codex ? palette.add : tool == .antigravity ? palette.g2 : palette.need
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(Color(color)).frame(width: 7, height: 7).neon(color, radius: 4)
                    Text(tool == .terminal ? "Düz Terminal" : tool.title).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(palette.text1))
                }
                .padding(.horizontal, 12)
                .frame(height: 29)
                .background(Color(palette.surface2))
                .cornerRadius(Theme.cornerCard, corners: [.topLeft, .topRight])
                VStack(alignment: .leading, spacing: 4) {
                    Text("~/proje % \(tool.command ?? "")").font(Theme.swiftFont(size: 14)).foregroundColor(Color(palette.terminalText))
                    Text(tool == .terminal ? "Hazır" : "Resmi program açılıyor").font(Theme.swiftFont(size: 14)).foregroundColor(Color(palette.text3))
                }
                // 12, like the tab above: the terminal text stands under the tab's dot.
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                .background(Color(palette.surface0))
                .cornerRadius(Theme.cornerCard, corners: [.topRight, .bottomLeft, .bottomRight])
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).stroke(Color(palette.hair2)))
            }
            .frame(maxWidth: 420)
        case .voice:
            VStack(spacing: 28) {
                VoiceBars()
                Text("❯ testleri çalıştır ve düzelt").font(Theme.swiftFont(size: 15)).foregroundColor(Color(palette.text1))
            }
        case .views:
            HStack(alignment: .top, spacing: 14) {
                boardColumn("Yapılacak", palette.text3, ["Giriş sayfası"])
                boardColumn("Sürüyor", palette.g1, ["Testleri düzelt", "Ödeme akışı"])
                boardColumn("Bitti", palette.add, ["Sürüm notu"])
            }
            .frame(maxWidth: 460)
        case .chat:
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Text("Testleri düzelt").font(.system(size: 14)).foregroundColor(Color(palette.text1)).padding(10).background(Color(palette.surface2)).cornerRadius(10)
                }
                Text("Üç test düzeltildi, hepsi geçiyor. Yayına alayım mı?").font(.system(size: 15)).lineSpacing(5).foregroundColor(Color(palette.text1))
                HStack {
                    Text("❯ Yanıt yazın").font(.system(size: 14)).foregroundColor(Color(palette.text3))
                    Spacer()
                }
                .frame(height: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(Color(palette.need)).frame(height: 2).neon(palette.need, radius: 4) }
                .padding(.top, 12)
            }
            .frame(maxWidth: 420)
        case .notch:
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: Theme.cornerFloat).fill(Color(palette.surface0))
                RoundedRectangle(cornerRadius: Theme.cornerFloat).stroke(Color(palette.hair2))
                HStack {
                    Circle().fill(Color(palette.g1)).frame(width: 9, height: 9).neon(palette.g1, radius: 4)
                    Spacer()
                    Circle().fill(Color(palette.need)).frame(width: 9, height: 9).neon(palette.need, radius: 4)
                }
                .padding(.horizontal, 14)
                .frame(width: 232, height: 32)
                .background(Color.black)
                .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
                .neon(palette.need, radius: 9)
            }
            .frame(width: 440, height: 230)
        case .notify:
            HStack(spacing: 14) {
                Text("⏎").font(.system(size: 20)).foregroundColor(Color(palette.need)).frame(width: 38, height: 38).background(Color(palette.terminal)).cornerRadius(Theme.cornerCard)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude Code Sizi Bekliyor").font(.system(size: 14, weight: .semibold)).foregroundColor(Color(palette.text1))
                    Text("Bir komut için onay istiyor.").font(.system(size: 13)).foregroundColor(Color(palette.text2))
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: 380)
            .background(Color(palette.surface1))
            .cornerRadius(Theme.cornerFloat)
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerFloat).stroke(Color(palette.need).opacity(0.5)))
            .neon(palette.need, radius: 10)
        case .awake:
            VStack(alignment: .leading, spacing: 14) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 44))
                    path.addLine(to: CGPoint(x: 130, y: 44))
                    path.addLine(to: CGPoint(x: 150, y: 14))
                    path.addLine(to: CGPoint(x: 170, y: 44))
                    path.addLine(to: CGPoint(x: 420, y: 44))
                }
                .stroke(Color(palette.need), lineWidth: 2)
                .neon(palette.need, radius: 5)
                .frame(width: 420, height: 60)
                Text("İş sürüyor. Mac uyanık.").font(Theme.swiftFont(size: 13)).foregroundColor(Color(palette.text2))
            }
        case .keys:
            HStack(spacing: 12) {
                keyCap("⌘", color: palette.hair2, text: palette.text1, glow: false)
                keyCap("K", color: palette.need, text: palette.need, glow: true)
            }
        case .phone:
            VStack(alignment: .leading, spacing: 14) {
                phoneRow("Claude Code", state: "Çalışıyor", color: palette.g1)
                phoneRow("Codex", state: "Onay İstiyor", color: palette.need)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 40, leading: 14, bottom: 14, trailing: 14))
            .frame(width: 196, height: 400, alignment: .topLeading)
            .background(Color(palette.surface0))
            .cornerRadius(32)
            .overlay(RoundedRectangle(cornerRadius: 32).stroke(Color(palette.hair2), lineWidth: 2))
        }
    }

    private func boardColumn(_ title: String, _ color: NSColor, _ cards: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Color(color)).frame(height: 2)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(color))
            ForEach(cards, id: \.self) { card in
                Text(card).font(.system(size: 13)).foregroundColor(Color(Theme.palette.text1)).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(Theme.palette.surface1)).cornerRadius(Theme.cornerControl)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func keyCap(_ text: String, color: NSColor, text textColor: NSColor, glow: Bool) -> some View {
        Text(text)
            .font(Theme.swiftFont(size: 34))
            .foregroundColor(Color(textColor))
            .frame(width: 84, height: 84)
            .background(Color(Theme.palette.surface1))
            .cornerRadius(Theme.cornerFloat)
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerFloat).stroke(Color(color)))
            .shadow(color: glow && Neon.on ? Color(color).opacity(0.5) : .clear, radius: 10)
    }

    private func phoneRow(_ title: String, state: String, color: NSColor) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Color(Theme.palette.text1))
            Text(state).font(.system(size: 12)).foregroundColor(Color(color))
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Rectangle().fill(Color(color)).frame(width: 2) }
    }
}

private struct VoiceBars: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    var body: some View {
        // Four frames a second, and only while this step is on screen.
        TimelineView(.periodic(from: .now, by: Motion.allowed ? 0.25 : 3600)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 4)
            HStack(spacing: 7) {
                ForEach(0..<7, id: \.self) { index in
                    let wave = abs(((tick + abs(index - 3)) % 6) - 3)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(Theme.palette.need))
                        .frame(width: 6, height: 20 + CGFloat(wave) * 14)
                        .neon(Theme.palette.need, radius: 4)
                }
            }
            .frame(height: 72)
        }
    }
}

/// One choice in the tour: a ring, the name and a quiet note.
private struct TourOption: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    static let height: CGFloat = 44
    let title: String
    let note: String
    let on: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(on ? Color(palette.need) : .clear)
                    .overlay(Circle().stroke(on ? Color(palette.need) : Color(hovering ? palette.focus.withAlphaComponent(0.35) : palette.hair2), lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .shadow(color: on && Neon.on ? Color(palette.need) : .clear, radius: 5)
                Text(title).font(.system(size: 14, weight: on ? .semibold : .regular)).foregroundColor(Color(palette.text1))
                Spacer()
                Text(note).font(.system(size: 12)).foregroundColor(Color(hovering ? palette.text2 : palette.text3))
            }
            .frame(height: Self.height)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Color(palette.hair)).frame(height: 1) }
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}

/// A stop on the tour's rail. No panel behind it, so the pointer lights the name and the ring.
private struct TourRailItem: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let title: String
    let done: Bool
    let here: Bool
    let height: CGFloat
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(done ? Color(palette.need) : Color(palette.terminal))
                    .overlay(Circle().stroke(done ? Color(palette.need) : Color(hovering ? palette.focus.withAlphaComponent(0.35) : palette.hair2), lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .shadow(color: here && Neon.on ? Color(palette.need) : .clear, radius: 6)
                Text(title)
                    .font(.system(size: 12, weight: here ? .semibold : .regular))
                    .foregroundColor(Color(here || hovering ? palette.text1 : palette.text3))
            }
            .frame(height: height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}

/// A word in the accent that does something. It underlines under the pointer.
private struct TourLink: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let title: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .underline(hovering)
                .foregroundColor(Color(Theme.palette.need))
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}

struct WelcomeFlow: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = SettingsStore.shared
    @State private var inTour = false
    var body: some View {
        ZStack {
            Color(Theme.palette.terminal)
            CornerGlows()
            if inTour {
                TourView(finish: finish).transition(.opacity)
            } else {
                WelcomeCover(begin: {
                    if Motion.allowed { withAnimation(.easeInOut(duration: 0.25)) { inTour = true } } else { inTour = true }
                }, finish: finish)
                .transition(.opacity)
            }
        }
        .onDisappear { markSeen() }
    }

    private func markSeen() {
        if !store.settings.seenWelcome { store.settings.seenWelcome = true }
    }

    private func finish() {
        markSeen()
        AppModel.shared.page = nil
    }
}

// MARK: Home

/// With no session open the window is one command line: type and press Enter.
struct HomeView: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var power = PowerCenter.shared
    @ObservedObject var accounts = AccountStore.shared
    @State private var text = ""
    @State private var found: [RecentConversation] = []
    @State private var swept = false
    private var groups: [RecentConversation.Group] {
        RecentConversation.grouped(RecentHiding.visible(found, store.settings), limit: 6)
    }
    @FocusState private var typing: Bool

    var body: some View {
        let palette = Theme.palette
        ZStack(alignment: .top) {
            Color(palette.terminal)
            CornerGlows(first: .top, second: .bottomTrailing)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The welcome's mark, smaller: the same letters, spacing and blinking block, so home reads as the same place.
                    HStack(spacing: 6) {
                        Text("enterm")
                            .font(Theme.swiftFont(bold: true, size: 40))
                            .tracking(-1.5)
                            .foregroundColor(Color(palette.text1))
                        BlinkingCursor(width: 15, height: 35)
                    }
                    .frame(height: 50)
                    commandLine.padding(.top, 24)
                    actions.padding(.top, 16)
                    if !groups.isEmpty { recents.padding(.top, 36) }
                }
                .frame(maxWidth: 720)
                .padding(EdgeInsets(top: 96, leading: 24, bottom: 56, trailing: 24))
                .frame(maxWidth: .infinity)
            }
            VStack {
                Spacer()
                HStack(spacing: 16) {
                    Button { Commands.perform("memory") } label: { MemoryLabel().contentShape(Rectangle()) }
                        .buttonStyle(.press)
                        .help("Bellek Ayrıntısı")
                    LimitSummaryButton(summary: limitSummary)
                    Spacer()
                    T("Her Şeyi Bul ⌘K", color: palette.text3, style: .secondary)
                }
                // As tall as the status line on the canvas, so the bar does not jump when a session opens.
                .padding(.horizontal, 20)
                .frame(height: 36)
                .background(Color(palette.terminal))
                .overlay(alignment: .top) { Line() }
            }
        }
        .onAppear {
            PowerCenter.shared.measureUsage()
            typing = true
            power.measureUsage()
            ToolCatalog.shared.refresh()
            let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
            DispatchQueue.global(qos: .utility).async {
                let scanned = RecentConversation.scan(projects: projects)
                DispatchQueue.main.async { found = scanned }
            }
            if Motion.allowed {
                withAnimation(.timingCurve(0.6, 0, 0.2, 1, duration: 0.6)) { swept = true }
            } else {
                swept = true
            }
        }
    }

    private var limitSummary: String { accounts.limitSummary }

    private var defaultTool: ToolKind {
        switch store.settings.defaultProgram {
        case "claude": return .claude
        case "codex": return .codex
        case "agy": return .antigravity
        default: return .terminal
        }
    }

    private var commandLine: some View {
        let palette = Theme.palette
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("❯").font(Theme.swiftFont(size: 16)).foregroundColor(Color(palette.need))
                TextField("Komut, klasör ya da proje yazın", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.swiftFont(size: 16))
                    .foregroundColor(Color(palette.text1))
                    .focused($typing)
                    .onSubmit(run)
                RunKey(action: run)
                    .help("Çalıştır")
            }
            .frame(height: 48)
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(palette.hair2)).frame(height: 1)
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color(palette.need))
                        .frame(width: swept ? geometry.size.width : 0, height: 2)
                        .neon(palette.need, radius: 5)
                }
                .frame(height: 2)
            }
        }
    }

    private var actions: some View {
        // The same gap across and down, so no two tiles touch.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ActionRow(title: "\(defaultTool == .terminal ? "Terminal" : defaultTool.title) Aç", key: "⏎", strong: true) { open(cwd: nil) }
            ActionRow(title: "Klasör Aç", key: "") { chooseFolder() }
            ActionRow(title: "Depo Klonla", key: "") {
                text = "git clone "
                typing = true
            }
            ActionRow(title: "SSH ile Bağlan", key: "") { Commands.perform("remote") }
        }
    }

    private var recents: some View {
        let palette = Theme.palette
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                T("Kaldığınız Yerden", color: palette.text2, style: .secondary, weight: .semibold)
                Spacer()
                Btn("Tümü", kind: .plain) { Commands.perform("recents") }
            }
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(groups.enumerated()), id: \.element.folder) { index, group in
                    let color = index.isMultiple(of: 2) ? palette.g1 : palette.g2
                    VStack(alignment: .leading, spacing: 2) {
                        RecentFolderHeader(folder: group.folder)
                        ForEach(group.items) { item in
                            RecentRow(item: item)
                        }
                    }
                    .padding(.leading, 22)
                    .overlay(alignment: .topLeading) {
                        ZStack(alignment: .top) {
                            Rectangle().fill(Color(color).opacity(0.55)).frame(width: 2).padding(.top, 8).padding(.bottom, 12)
                            Circle()
                                .fill(Color(palette.terminal))
                                .overlay(Circle().stroke(Color(color), lineWidth: 2))
                                .frame(width: 12, height: 12)
                                .neon(color, radius: 4)
                                .padding(.top, 3)
                        }
                        .frame(width: 12)
                    }
                }
            }
        }
    }

    private func open(cwd: String?) {
        let tool = defaultTool
        model.startingFromHome = true
        if tool == .terminal {
            model.newTerminal(cwd: cwd)
        } else {
            ToolLauncher.start(tool, cwd: cwd)
        }
    }

    private func run() {
        let intent = HomeInput.parse(text, home: NSHomeDirectory()) { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        }
        text = ""
        switch intent {
        // With a project already open, a plain start is a new project, not one more box in it.
        case .open: open(cwd: model.sessions.isEmpty ? nil : NSHomeDirectory())
        case .folder(let path): open(cwd: path)
        case .command(let line):
            model.startingFromHome = true
            model.newTerminal(cwd: NSHomeDirectory(), startup: line)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Aç"
        if panel.runModal() == .OK, let url = panel.url { open(cwd: url.path) }
    }
}

private struct ActionRow: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let title: String
    let key: String
    var strong = false
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(.system(size: 14, weight: strong ? .semibold : .regular)).foregroundColor(Color(palette.text1))
                Spacer()
                // The key reads like every other key hint in the app: quiet text, no badge.
                if !key.isEmpty { Key(key) }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(strong ? Color(palette.need).opacity(hovering ? 0.14 : 0.09) : (hovering ? Color(palette.fill) : .clear))
            .cornerRadius(Theme.cornerControl)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerControl)
                    .strokeBorder(strong ? Color(palette.need).opacity(0.35) : Color(hovering ? palette.focus.withAlphaComponent(0.35) : palette.hair2), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}

/// The home line's Enter key. A quiet square like an icon button: the lit line under the field is the accent here.
private struct RunKey: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            Text("⏎")
                .font(.system(size: 13))
                .foregroundColor(Color(hovering ? palette.text1 : palette.text2))
                .frame(width: 30, height: 30)
                .background(hovering ? Color(palette.fill) : .clear)
                .cornerRadius(Theme.cornerControl)
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerControl).strokeBorder(Color(hovering ? palette.focus.withAlphaComponent(0.35) : palette.hair2), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}

/// Every recent conversation, by folder.
struct RecentsPage: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var found: [RecentConversation] = []
    @State private var loaded = false
    private var groups: [RecentConversation.Group] {
        RecentConversation.grouped(RecentHiding.visible(found, store.settings), limit: 80)
    }
    var body: some View {
        PageFrame(title: "Geçmiş Konuşmalar") {
            if loaded, groups.isEmpty { Dim("Henüz Claude Code konuşması yok.") }
            if RecentHiding.count(store.settings) > 0 {
                HStack(spacing: 12) {
                    Dim("\(RecentHiding.count(store.settings)) öğe listeden kaldırıldı. Konuşma kayıtları yerinde duruyor.")
                    Spacer(minLength: 0)
                    Btn("Hepsini Geri Getir", kind: .plain) { RecentHiding.restoreAll() }
                }
            }
            ForEach(groups, id: \.folder) { group in
                VStack(alignment: .leading, spacing: 4) {
                    T((group.folder as NSString).lastPathComponent, bold: true)
                    Dim(AppModel.shared.displayPath(group.folder)).lineLimit(1).truncationMode(.head)
                    Panel {
                        MenuList { ForEach(group.items) { item in RecentRow(item: item) } }
                    }
                }
            }
        }
        .onAppear {
            let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
            DispatchQueue.global(qos: .utility).async {
                let scanned = RecentConversation.scan(projects: projects, newest: 80)
                DispatchQueue.main.async {
                    found = scanned
                    loaded = true
                }
            }
        }
    }
}

private struct RecentRow: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let item: RecentConversation
    @State private var hovering = false
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.unitsStyle = .short
        return formatter
    }()
    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 8) {
            Button {
                AppModel.shared.startingFromHome = true
                ToolLauncher.start(.claude, cwd: item.folder, extraArguments: "--resume \(NotFoundActions.shellQuote(item.id))")
            } label: {
                HStack(spacing: 10) {
                    Text(item.title).font(.system(size: 13)).foregroundColor(Color(palette.text1)).lineLimit(1)
                    Text("Claude Code").font(.system(size: 12)).foregroundColor(Color(palette.text3))
                    Spacer(minLength: 8)
                    Text(hovering ? "Sürdür ⏎" : Self.relative.localizedString(for: item.modified, relativeTo: Date()))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hovering ? palette.need : palette.text3))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            // Always in place, seen only under the pointer: the row does not shift when it appears.
            RemoveKey(help: "Listeden Kaldır") { RecentHiding.hide(item) }
                .opacity(hovering ? 1 : 0)
        }
        // The same 10 on every side as a menu row, so a lit row looks even.
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(hovering ? Color(palette.fill) : .clear)
        .cornerRadius(Theme.cornerControl)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Listeden Kaldır") { RecentHiding.hide(item) }
            Button("Bu Klasörü Listeden Kaldır") { RecentHiding.hideFolder(item.folder) }
        }
    }
}

/// A folder's name over its conversations. Under the pointer it offers to take the whole folder off the list.
private struct RecentFolderHeader: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let folder: String
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text((folder as NSString).lastPathComponent).font(.system(size: 13, weight: .semibold)).foregroundColor(Color(palette.text1))
                Text(AppModel.shared.displayPath(folder)).font(Theme.swiftFont(size: 11)).foregroundColor(Color(palette.text3)).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            RemoveKey(help: "Bu Klasörü Listeden Kaldır") { RecentHiding.hideFolder(folder) }
                .opacity(hovering ? 1 : 0)
        }
        // The same 10 as the text inside a row, so the folder name lines up with its rows.
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Bu Klasörü Listeden Kaldır") { RecentHiding.hideFolder(folder) }
        }
    }
}

/// A small ✕ that lights under the pointer, for taking one thing off a list.
private struct RemoveKey: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let help: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            Symbol("xmark", color: hovering ? palette.text1 : palette.text3, size: 10)
                .frame(width: 18, height: 18)
                .background(hovering ? Color(palette.fillSelected) : .clear)
                .cornerRadius(Theme.cornerControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Taking conversations off the home list and bringing them back. The program's transcripts stay as they are.
enum RecentHiding {
    static func visible(_ items: [RecentConversation], _ settings: AppSettings) -> [RecentConversation] {
        RecentConversation.visible(items, hidingConversations: settings.hiddenConversations, hidingFolders: settings.hiddenConversationFolders)
    }
    static func count(_ settings: AppSettings) -> Int {
        settings.hiddenConversations.count + settings.hiddenConversationFolders.count
    }
    static func hide(_ item: RecentConversation) {
        let store = SettingsStore.shared
        if !store.settings.hiddenConversations.contains(item.id) { store.settings.hiddenConversations.append(item.id) }
    }
    static func hideFolder(_ folder: String) {
        let store = SettingsStore.shared
        if !store.settings.hiddenConversationFolders.contains(folder) { store.settings.hiddenConversationFolders.append(folder) }
    }
    static func restoreAll() {
        SettingsStore.shared.settings.hiddenConversations = []
        SettingsStore.shared.settings.hiddenConversationFolders = []
    }
}

/// The programs' limits in one line. A click opens Kullanım, where each account has its own row.
struct LimitSummaryButton: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject private var accounts = AccountStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    let summary: String
    /// Where the line is shared with other things, only the short form is offered.
    var roomy = true
    var body: some View {
        if !summary.isEmpty {
            Button { AppModel.shared.page = .settings(.usage) } label: {
                // The most that fits: with the weekly reset, with the weekly bar, or the current window alone.
                ViewThatFits(in: .horizontal) {
                    if roomy {
                        row { entry($0, week: true, reset: true) }
                        row { entry($0, week: true, reset: false) }
                    }
                    row { entry($0, week: false, reset: false) }
                    T(summary, color: Theme.palette.text2, style: .secondary).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .help("Limit Ayrıntısı")
        }
    }

    private var known: [Account] { accounts.accounts.filter { $0.lastLimit?.fiveHour != nil || $0.lastLimit?.sevenDay != nil } }

    private func row<Content: View>(@ViewBuilder _ content: @escaping (Account) -> Content) -> some View {
        HStack(spacing: 16) {
            ForEach(known) { content($0) }
        }
        .fixedSize()
    }

    private func entry(_ account: Account, week: Bool, reset: Bool) -> some View {
        let label = account.kind == .system ? account.tool.title : "\(account.tool.title) (\(account.name))"
        let five = account.lastLimit?.fiveHour
        let seven = account.lastLimit?.sevenDay
        return HStack(spacing: 8) {
            T(label, color: Theme.palette.text2, style: .secondary)
            if let window = five ?? seven {
                gauge(title: five == nil ? "H" : nil, window, help: five == nil ? "Haftalık" : "5 Saatlik")
            }
            if week, five != nil, let seven {
                gauge(title: "Hafta", seven, help: "Haftalık")
                if reset, let date = seven.resetsAt, date > Date() {
                    T(TimeText.short(date), color: Theme.palette.text3, style: .secondary)
                        .help(TimeText.reset(date))
                }
            }
        }
    }

    private func gauge(title: String?, _ window: LimitWindow, help: String) -> some View {
        let used = window.usedPercent
        let remaining = settings.settings.usageRemaining
        let value = remaining ? 100 - used : used
        return HStack(spacing: 6) {
            if let title { T(title, color: Theme.palette.text3, style: .secondary) }
            Meter(percent: value, tone: UsageTone.color(used: used)).frame(width: 44)
            T("%\(Int(value))", color: Theme.palette.text1, style: .secondary).monospacedDigit()
        }
        .help("\(help): %\(Int(value)) \(remaining ? "Kaldı" : "Dolu")")
    }
}

struct MemoryLabel: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var power = PowerCenter.shared
    var body: some View {
        if power.enterm.memoryMB > 0 {
            HStack(spacing: 6) {
                Circle().fill(Color(Theme.palette.add)).frame(width: 7, height: 7).neon(Theme.palette.add, radius: 3)
                T("Enterm \(Int(power.enterm.memoryMB)) MB", color: Theme.palette.text2, style: .secondary)
            }
        }
    }
}

// MARK: Rail and command bar

/// The sessions as a line with stops. Whoever needs the person comes first. No panel behind it.
struct SessionRail: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    var body: some View {
        let palette = Theme.palette
        ScrollView(showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                let list = RailOrder.sorted(model.visibleSessions) { $0.status }
                if list.count > 1 {
                    Rectangle().fill(Color(palette.hair2)).frame(width: 2, height: 44 * CGFloat(list.count - 1)).padding(.leading, 5).padding(.top, 22)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(list) { info in
                        RailStop(info: info)
                    }
                }
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 8))
        }
        .background(Color(palette.surface0).opacity(0.001))
    }
}

/// One stop on the rail. No panel behind it, so the pointer lights the name and the ring.
private struct RailStop: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    let info: SessionInfo
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        let unread = model.unread.contains(info.number)
        let light = Neon.color(info) ?? (unread ? palette.add : nil)
        let color = light ?? palette.text3
        let on = info.number == model.focused
        let attention = info.status == .needsApproval || info.status == .limitReached || info.status == .failed
        Button { model.setFocus(info.number) } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(palette.surface0))
                    .overlay(Circle().stroke(Color(light == nil && hovering ? palette.focus.withAlphaComponent(0.35) : color), lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .shadow(color: light != nil && Neon.on ? Color(color) : .clear, radius: Neon.radius)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name(for: info))
                        .font(.system(size: 12, weight: on || attention ? .semibold : .regular))
                        .foregroundColor(Color(on || attention || hovering ? palette.text1 : palette.text2))
                        .lineLimit(1)
                    Text(info.tool == .terminal ? AppModel.projectName(for: info.cwd) : (unread ? "Yeni Yanıt" : (info.status == .failed ? info.failure?.title ?? info.status.title : info.status.title)))
                        .font(.system(size: 11))
                        .foregroundColor(Color(info.tool == .terminal ? palette.text3 : color))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .help(SessionText.failureNote(info) ?? "")
        .onHover { hovering = $0 }
    }
}

/// One line instead of a row of icons: everything the app does is a word away.
struct CommandBar: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 10) {
            Button { Commands.perform("palette") } label: {
                HStack(spacing: 10) {
                    Text("❯").font(Theme.swiftFont(size: 14)).foregroundColor(Color(palette.need))
                    T("Komut yazın ya da oturum arayın", color: hovering ? palette.text2 : palette.text3)
                    Spacer(minLength: 8)
                    Key("⌘K")
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .onHover { hovering = $0 }
            Button { Commands.perform("newSession") } label: {
                Symbol("plus", color: palette.btnfg, size: 14)
                    .frame(width: 30, height: 30)
                    .background(Color(palette.btn))
                    .cornerRadius(Theme.cornerControl)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .help("Yeni Oturum")
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(width: 440, height: 44)
        .background(Color(palette.surface1))
        .cornerRadius(Theme.cornerCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).stroke(Color(hovering ? palette.focus.withAlphaComponent(0.35) : palette.hair2)))
        .shadow(color: Color(palette.shadowFloat), radius: 12, y: 8)
    }
}

/// The slim line under the canvas. A plain terminal never sees it.
struct StatusLine: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    let summary: String
    // Once when it appears, then rarely and only while the app is in use: it starts a process.
    @State private var ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 16) {
            Button { Commands.perform("memory") } label: { MemoryLabel().contentShape(Rectangle()) }
                .buttonStyle(.press)
                .help("Bellek Kullanımı")
            LimitSummaryButton(summary: summary)
            Spacer(minLength: 0)
            if model.toolbarVisible {
                HStack(spacing: 2) {
                    IconBtn(model.canvasLocked ? "lock.fill" : "lock.open", label: "Tuval Kilidi", active: model.canvasLocked) { Commands.perform("lockCanvas") }
                        .help(model.canvasLocked ? "Tuval Kilitli" : "Tuvali Kilitle")
                    IconBtn("minus", label: "Uzaklaştır") { Commands.perform("zoomOut") }
                    ZoomFitButton(zoom: model.zoom)
                        .help("Sığdır (0)")
                    IconBtn("plus", label: "Yakınlaştır") { Commands.perform("zoomIn") }
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 36)
        .background(Color(palette.surface0))
        .overlay(alignment: .top) { Line() }
        .onAppear { PowerCenter.shared.measureUsage() }
        .onReceive(ticker) { _ in
            if NSApp.isActive { PowerCenter.shared.measureUsage() }
        }
    }
}

/// The zoom level between the two zoom buttons: as tall as they are, and lit the same way under the pointer.
private struct ZoomFitButton: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let zoom: CGFloat
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button { Commands.perform("fit") } label: {
            T("%\(Int(zoom * 100))", color: hovering ? palette.text1 : palette.text2, style: .secondary)
                .frame(width: 40, height: 30)
                .background(hovering ? Color(palette.fill) : .clear)
                .cornerRadius(Theme.cornerControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}
