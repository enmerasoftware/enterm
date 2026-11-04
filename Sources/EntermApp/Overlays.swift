import AppKit
import EntermCore
import SwiftUI

struct OverlayRouter: View {
    let overlay: Overlay
    var body: some View {
        switch overlay {
        case .palette: Scrim(alignment: .top) { CommandPalette() }
        case .newSession: Scrim(alignment: .topTrailing) { NewSessionMenu() }
        case .menu: Scrim(alignment: .topTrailing) { MainMenuPanel() }
        case .newSessionOptions: Scrim(alignment: .top) { NewSessionOptions() }
        case .linkPermission(let from, let to): Scrim(alignment: .top) { LinkPermissionDialog(from: from, to: to) }
        case .linkDetail(let id): Scrim(alignment: .top) { LinkDetailDialog(id: id) }
        case .approval(let id): Scrim(alignment: .top) { ApprovalDialog(id: id) }
        case .limit(let number): Scrim(alignment: .top) { LimitDialog(number: number) }
        case .sshList(let id): Scrim(alignment: .top) { SSHListDialog(sessionID: id) }
        case .remoteLost(let number): Scrim(alignment: .top) { RemoteLostDialog(number: number) }
        case .limitOpened: Scrim(alignment: .top) { LimitOpenedDialog() }
        case .resumeFailed(let number): Scrim(alignment: .top) { ResumeFailedDialog(number: number) }
        case .installTool(let tool): Scrim(alignment: .top) { InstallToolDialog(tool: tool) }
        case .codexLimit(let number): Scrim(alignment: .top) { CodexLimitDialog(number: number) }
        }
    }
}

struct Scrim<Content: View>: View {
    var alignment: Alignment
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack(alignment: alignment) {
            Color(alignment == .topTrailing ? .clear : Theme.palette.scrim)
                .contentShape(Rectangle())
                .onTapGesture { AppModel.shared.overlay = nil }
            content()
                .padding(.top, alignment == .topTrailing ? 44 : 72)
                .padding(.trailing, alignment == .topTrailing ? 16 : 0)
        }
    }
}

struct MenuRow: View {
    let title: String
    var note = ""
    var key = ""
    var selected = false
    let action: () -> Void
    var body: some View {
        Row(selected: selected, action: action) {
            VStack(alignment: .leading, spacing: 0) {
                T(title)
                if !note.isEmpty { Dim(note) }
            }
            Spacer(minLength: 16)
            if !key.isEmpty { Key(key) }
        }
    }
}

/// ⌘K: type to filter, arrows to move, Enter to run.
struct CommandPalette: View {
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focus: Bool

    var results: [Command] {
        let needle = query.lowercased(with: Locale(identifier: "tr_TR"))
        if needle.isEmpty { return Commands.all }
        return Commands.all.filter { $0.title.lowercased(with: Locale(identifier: "tr_TR")).contains(needle) }
    }

    var body: some View {
        Panel {
            HStack(spacing: 8) {
                T(">", color: Theme.palette.dim)
                TextField("", text: $query, prompt: Text("Ne Yapmak İstersiniz?").foregroundColor(Color(Theme.palette.dim)))
                    .textFieldStyle(.plain)
                    .font(Theme.swiftFont())
                    .foregroundColor(Color(Theme.palette.fg))
                    .focused($focus)
                    .onSubmit(run)
                    .onChange(of: query) { _ in index = 0 }
            }
            .padding(12)
            Line()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { offset, command in
                        MenuRow(title: command.title, key: command.key, selected: offset == index) {
                            perform(command)
                        }
                    }
                }
            }
            .frame(maxHeight: 340)
            Line()
            HStack {
                Dim("↑↓ Gez · ⏎ Çalıştır · Esc Kapat")
                Spacer()
                Dim("Her İş Klavyeden Yapılır")
            }
            .padding(.horizontal, 12)
            .frame(height: 24)
        }
        .frame(width: 560)
        .background(KeyCatcher(onUp: { index = max(0, index - 1) }, onDown: { index = min(results.count - 1, index + 1) }))
        .onAppear { focus = true }
    }

    private func run() {
        guard index < results.count else { return }
        perform(results[index])
    }

    private func perform(_ command: Command) {
        AppModel.shared.overlay = nil
        DispatchQueue.main.async { Commands.perform(command.id) }
    }
}

/// Up and down arrows while a text field keeps the focus.
struct KeyCatcher: NSViewRepresentable {
    var onUp: () -> Void
    var onDown: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: context.coordinator.up?(); return nil
            case 125: context.coordinator.down?(); return nil
            default: return event
            }
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.up = onUp
        context.coordinator.down = onDown
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }
    final class Coordinator {
        var monitor: Any?
        var up: (() -> Void)?
        var down: (() -> Void)?
    }
}

/// A program that is not installed: the reason and the command, before any box opens.
struct InstallToolDialog: View {
    let tool: ToolKind
    var body: some View {
        Panel {
            PanelHeader(title: "\(tool.title) Bu Bilgisayarda Kurulu Değil")
            VStack(alignment: .leading, spacing: 8) {
                let command = ToolPresence.installCommand(tool) ?? ""
                HStack {
                    T(command).lineLimit(1).textSelection(.enabled)
                    Spacer()
                    Btn("Kopyala", kind: .plain) { NotFoundActions.copy(command) }
                }
                Dim("\(tool.title)'in Resmî Kurulum Komutu. Siz Onaylamadan Çalışmaz, Onaylarsanız Yeni Terminalde Görünür Şekilde Çalışır.")
                HStack {
                    Btn("Yeni Terminalde Çalıştır", kind: .primary, key: "⏎") { InstallToolActions.run(tool) }
                    Btn("Vazgeç", kind: .plain, key: "Esc") { AppModel.shared.overlay = nil }
                }
            }
            .padding(12)
        }
        .frame(width: 560)
    }
}

enum InstallToolActions {
    static func run(_ tool: ToolKind) {
        let model = AppModel.shared
        model.overlay = nil
        guard let command = ToolPresence.installCommand(tool) else { return }
        var spec = SessionSpec(name: "\(tool.title) Kurulumu", tool: .terminal, cwd: NSHomeDirectory(), rows: 30, cols: 100)
        spec.env = ["ENTERM_STARTUP": command]
        model.create(spec)
    }
}

struct NewSessionMenu: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var catalog = ToolCatalog.shared
    var body: some View {
        Panel {
            PanelHeader(title: "Yeni Oturum") { Dim(model.displayPath(model.focusedInfo?.cwd ?? NSHomeDirectory())) }
            MenuRow(title: "Terminal", key: "⌘T") { run("newTerminal") }
            MenuRow(title: "Claude Code", note: catalog.note(.claude), key: "c") { run("newClaude") }
            MenuRow(title: "Codex", note: catalog.note(.codex), key: "x") { run("newCodex") }
            MenuRow(title: "Antigravity", note: catalog.note(.antigravity).isEmpty ? "Gemini" : "Gemini · \(catalog.note(.antigravity))", key: "a") { run("newAntigravity") }
            Line()
            MenuRow(title: "Seçeneklerle Aç", note: "Klasör, Hesap, Yetki, Model") { run("newSessionOptions") }
            Line()
            HStack { Dim("Tek Tıkla Açılır, Gerisi Hazır Gelir") }.padding(.horizontal, 12).frame(height: 24)
        }
        .frame(width: 400)
        .background(LetterKeys(map: ["c": "newClaude", "x": "newCodex", "a": "newAntigravity"]))
        .onAppear { catalog.refresh() }
    }
    private func run(_ id: String) {
        model.overlay = nil
        DispatchQueue.main.async { Commands.perform(id) }
    }
}

struct LetterKeys: NSViewRepresentable {
    let map: [String: String]
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let keys = map
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  let letter = event.charactersIgnoringModifiers, let id = keys[letter] else { return event }
            AppModel.shared.overlay = nil
            DispatchQueue.main.async { Commands.perform(id) }
            return nil
        }
        return NSView()
    }
    func updateNSView(_ view: NSView, context: Context) {}
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }
    final class Coordinator { var monitor: Any? }
}

struct MainMenuPanel: View {
    var body: some View {
        Panel {
            item("Yeni Terminal", key: "⌘T", id: "newTerminal")
            Line()
            item("Yeni Görünüm", note: "Dosyalar, Düzenleyici, Not", id: "newView")
            item("Pano", note: "Kartlar, Üyeler, Son Tarihler", id: "board")
            item("Konuşarak Yaz", note: "Konuşun, Yazıya Dönsün", key: "⌃⌘ Basılı", id: "voice")
            item("Geçmiş Konuşmalar", note: "Açın, Sürdürün", id: "history")
            item("Uzak Sunucu", note: "SSH İle Proje Açın", id: "remote")
            item("Değişiklikler Ve Git", note: "Hazırla, Commit, Push", id: "changes")
            item("Ekibini Kur", note: "Birkaç Claude Code Birlikte Çalışır", id: "team")
            item("Hesaplar", note: "Claude Code, Codex, Antigravity Girişleri", id: "accounts")
            item("Telefonu Bağla", note: "Bu Terminali Telefonda Açın", id: "phone")
            Line()
            item("Ayarlar", key: "⌘,", id: "settings")
            item("Tüm Komutlar", key: "⌘K", id: "palette")
        }
        .frame(width: 400)
    }
    private func item(_ title: String, note: String = "", key: String = "", id: String) -> some View {
        MenuRow(title: title, note: note, key: key) {
            AppModel.shared.overlay = nil
            DispatchQueue.main.async { Commands.perform(id) }
        }
    }
}
