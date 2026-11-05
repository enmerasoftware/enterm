import AppKit
import EntermCore
import SwiftUI

struct OverlayRouter: View {
    @ObservedObject private var appearance = AppearanceTick.shared
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
        case .input: Scrim(alignment: .top) { InputDialog() }
        case .confirm: Scrim(alignment: .top) { ConfirmDialog() }
        case .memory: Scrim(alignment: .bottomLeading) { MemoryPanel() }
        }
    }
}

struct Scrim<Content: View>: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    var alignment: Alignment
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack(alignment: alignment) {
            Color(alignment == .top ? Theme.palette.scrim : .clear)
                .contentShape(Rectangle())
                .onTapGesture { AppModel.shared.overlay = nil }
            content()
                .environment(\.floatingPanel, true)
                .padding(.top, alignment == .topTrailing ? 44 : (alignment == .top ? 72 : 0))
                .padding(.trailing, alignment == .topTrailing ? 16 : 0)
                .padding(.bottom, alignment == .bottomLeading ? 44 : 0)
                .padding(.leading, alignment == .bottomLeading ? 16 : 0)
        }
    }
}

struct MenuRow: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let title: String
    var note = ""
    var key = ""
    var selected = false
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    T(title)
                    if !note.isEmpty { Dim(note) }
                }
                Spacer(minLength: 16)
                if !key.isEmpty { Key(key) }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(selected || hovering ? Color(Theme.palette.fillSelected) : .clear)
            .cornerRadius(Theme.cornerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// ⌘K: type to filter, arrows to move, Enter to run.
struct CommandPalette: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focus: Bool

    var results: [Command] {
        let needle = query.lowercased(with: Locale(identifier: "tr_TR"))
        let all = Commands.dynamic + Commands.all
        if needle.isEmpty { return all }
        return all.filter { $0.title.lowercased(with: Locale(identifier: "tr_TR")).contains(needle) }
    }

    var body: some View {
        Panel {
            HStack(spacing: 8) {
                Text("❯").font(Theme.swiftFont(size: 15)).foregroundColor(Color(Theme.palette.need))
                TextField("", text: $query, prompt: Text("Ne Yapmak İstersiniz?").foregroundColor(Color(Theme.palette.text3)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(Color(Theme.palette.fg))
                    .focused($focus)
                    .onSubmit(run)
                    .onChange(of: query) { _ in index = 0 }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            Line()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { offset, command in
                        MenuRow(title: command.title, key: command.key, selected: offset == index) {
                            perform(command)
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 340)
            Line()
            HStack {
                Dim("↑↓ Gez · ⏎ Çalıştır · Esc Kapat")
                Spacer()
                Dim("Her İş Klavyeden Yapılır")
            }
            .padding(.horizontal, 16)
            .frame(height: 32)
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
    private var explanation: String {
        var source = "\(tool.title) için üreticinin kurulum komutu."
        if tool == .gemini { source += " Kişisel Google hesabı için Antigravity daha uygundur." }
        return "\(source) Siz onaylamadan çalışmaz, onaylarsanız yeni terminalde görünür şekilde çalışır."
    }
    var body: some View {
        Panel {
            PanelHeader(title: "\(tool.title) Bu Bilgisayarda Kurulu Değil")
            VStack(alignment: .leading, spacing: 12) {
                CommandBox(text: ToolPresence.installCommand(tool) ?? "")
                Dim(explanation).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            DialogButtons {
                Btn("Vazgeç", kind: .plain, key: "Esc") { AppModel.shared.overlay = nil }
                Btn("Yeni Terminalde Çalıştır", kind: .primary, key: "⏎") { InstallToolActions.run(tool) }
            }
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
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var catalog = ToolCatalog.shared
    @ObservedObject var store = SettingsStore.shared
    private static let letters: [ToolKind: String] = [.claude: "c", .codex: "x", .antigravity: "a", .gemini: "g", .opencode: "o", .grok: "r", .copilot: "p", .cursor: "u"]
    @State private var showAll = false
    private var programs: [ToolKind] { ToolKind.programs.filter { !store.settings.hiddenTools.contains($0.rawValue) } }
    private var ready: [ToolKind] { programs.filter { !catalog.isMissing($0) } }
    private var missing: [ToolKind] { programs.filter { catalog.isMissing($0) } }
    var body: some View {
        Panel {
            PanelHeader(title: "Yeni Oturum") { Dim(model.displayPath(model.focusedInfo?.cwd ?? NSHomeDirectory())).lineLimit(1).truncationMode(.head) }
            VStack(spacing: 0) {
                MenuRow(title: "Terminal", key: "⌘T") { run { model.newTerminal() } }
                ForEach(ready, id: \.self) { tool in
                    MenuRow(title: tool.title, note: catalog.note(tool), key: Self.letters[tool] ?? "") { run { ToolLauncher.start(tool) } }
                }
                ForEach(store.settings.customPrograms) { program in
                    MenuRow(title: program.name, note: program.command) { run { ToolLauncher.start(program) } }
                }
                if !missing.isEmpty {
                    if showAll {
                        Line().padding(.vertical, 4)
                        ForEach(missing, id: \.self) { tool in
                            MenuRow(title: tool.title, note: "Kurulu Değil", key: Self.letters[tool] ?? "") { run { ToolLauncher.start(tool) } }
                        }
                    } else {
                        MenuRow(title: "Diğer Programlar", note: "\(missing.count) Program Kurulabilir") { showAll = true }
                    }
                }
                Line().padding(.vertical, 4)
                MenuRow(title: "Seçeneklerle Aç", note: "Klasör, Hesap, Yetki, Model") { run { Commands.perform("newSessionOptions") } }
            }
            .padding(4)
        }
        .frame(width: 340)
        .background(LetterKeys(actions: Dictionary(uniqueKeysWithValues: programs.compactMap { tool in
            Self.letters[tool].map { ($0, { ToolLauncher.start(tool) }) }
        })))
        .onAppear { catalog.refresh() }
    }
    private func run(_ action: @escaping () -> Void) {
        model.overlay = nil
        DispatchQueue.main.async(execute: action)
    }
}

struct LetterKeys: NSViewRepresentable {
    let actions: [String: () -> Void]
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let keys = actions
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  let letter = event.charactersIgnoringModifiers, let action = keys[letter] else { return event }
            AppModel.shared.overlay = nil
            DispatchQueue.main.async(execute: action)
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
    @ObservedObject private var appearance = AppearanceTick.shared
    var body: some View {
        Panel {
            VStack(spacing: 0) {
            item("Yeni Terminal", key: "⌘T", id: "newTerminal")
            Line().padding(.vertical, 4)
            item("Yeni Görünüm", note: "Dosyalar, Düzenleyici, Not", id: "newView")
            item("Pano", note: "Kartlar, Üyeler, Son Tarihler", id: "board")
            item("Konuşarak Yaz", note: "Konuşun, Yazıya Dönsün", key: "⌃⌘ Basılı", id: "voice")
            item("Geçmiş Konuşmalar", note: "Açın, Sürdürün", id: "history")
            item("Uzak Sunucu", note: "SSH İle Proje Açın", id: "remote")
            item("Değişiklikler Ve Git", note: "Hazırla, Commit, Push", id: "changes")
            item("Ekibini Kur", note: "Birkaç Claude Code Birlikte Çalışır", id: "team")
            item("Hesaplar", note: "Claude Code, Codex, Antigravity Girişleri", id: "accounts")
            item("Telefonu Bağla", note: "Bu Terminali Telefonda Açın", id: "phone")
            Line().padding(.vertical, 4)
            item("Ayarlar", key: "⌘,", id: "settings")
            item("Tüm Komutlar", key: "⌘K", id: "palette")
            }
            .padding(4)
        }
        .frame(width: 320)
    }
    private func item(_ title: String, note: String = "", key: String = "", id: String) -> some View {
        MenuRow(title: title, note: note, key: key) {
            AppModel.shared.overlay = nil
            DispatchQueue.main.async { Commands.perform(id) }
        }
    }
}
