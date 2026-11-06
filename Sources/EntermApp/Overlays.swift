import AppKit
import EntermCore
import SwiftUI

struct OverlayRouter: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let overlay: Overlay
    var body: some View {
        switch overlay {
        case .palette: Scrim(alignment: .center) { CommandPalette() }
        case .newSession: Scrim(alignment: .topTrailing) { NewSessionMenu() }
        case .menu: Scrim(alignment: .topTrailing) { MainMenuPanel() }
        case .newSessionOptions: Scrim(alignment: .center) { NewSessionOptions() }
        case .linkPermission(let from, let to): Scrim(alignment: .center) { LinkPermissionDialog(from: from, to: to) }
        case .linkDetail(let id): Scrim(alignment: .center) { LinkDetailDialog(id: id) }
        case .approval(let id): Scrim(alignment: .center) { ApprovalDialog(id: id) }
        case .limit(let number): Scrim(alignment: .center) { LimitDialog(number: number) }
        case .sshList(let id): Scrim(alignment: .center) { SSHListDialog(sessionID: id) }
        case .remoteLost(let number): Scrim(alignment: .center) { RemoteLostDialog(number: number) }
        case .limitOpened: Scrim(alignment: .center) { LimitOpenedDialog() }
        case .resumeFailed(let number): Scrim(alignment: .center) { ResumeFailedDialog(number: number) }
        case .installTool(let tool): Scrim(alignment: .center) { InstallToolDialog(tool: tool) }
        case .codexLimit(let number): Scrim(alignment: .center) { CodexLimitDialog(number: number) }
        case .input: Scrim(alignment: .center) { InputDialog() }
        case .confirm: Scrim(alignment: .center) { ConfirmDialog() }
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
            Color(alignment == .top || alignment == .center ? Theme.palette.scrim : .clear)
                .contentShape(Rectangle())
                .onTapGesture { AppModel.shared.overlay = nil }
            content()
                .environment(\.floatingPanel, true)
                // A centered dialog sits a little above the middle and keeps 16 from the top in a short window.
                // A menu keeps 16 from the bottom, where it starts to scroll.
                .padding(.top, alignment == .topTrailing ? 44 : (alignment == .top ? 72 : (alignment == .center ? 16 : 0)))
                .padding(.trailing, alignment == .topTrailing ? 16 : 0)
                .padding(.bottom, alignment == .bottomLeading ? 44 : (alignment == .center ? 60 : (alignment == .topTrailing ? 16 : 0)))
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
            // The same space on every side of the text, so a lit row looks even.
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(selected || hovering ? Color(Theme.palette.fillSelected) : .clear)
            .cornerRadius(Theme.cornerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}

/// A menu's rows. The same 10 around the list as inside a row, so a lit row has the same space on all four sides.
/// Rows are apart by one small gap, never by two paddings added together.
/// Row text starts where a panel title does: 10 here and 10 inside the row make the title's 20.
struct MenuList<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: MenuList.gap) { content() }.padding(10)
    }
    static var gap: CGFloat { 2 }
}

/// A line between groups of rows, 10 from the row above and the row below, like the list's edges.
struct MenuDivider: View {
    var body: some View { Line().padding(.vertical, 10 - MenuList<EmptyView>.gap) }
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
            // 20 at the sides: the prompt, the row titles and the hints share one edge.
            .padding(.horizontal, 20)
            .frame(height: 48)
            Line()
            ScrollView {
                MenuList {
                    ForEach(Array(results.enumerated()), id: \.element.id) { offset, command in
                        MenuRow(title: command.title, key: command.key, selected: offset == index) {
                            perform(command)
                        }
                    }
                }
            }
            // 340 whenever the window has room: in the middle of the window a list that shrank while typing would move the field.
            // A short window gets a shorter list instead of a palette cut at its top.
            .frame(minHeight: 120, maxHeight: 340)
            Line()
            HStack {
                Dim("↑↓ Gez · ⏎ Çalıştır · Esc Kapat")
                Spacer()
                Dim("Her İş Klavyeden Yapılır")
            }
            // The same band as the field bar above.
            .padding(.horizontal, 20)
            .frame(height: 48)
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
            .padding(20)
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
            // Whole when the window is tall enough, scrolling when it is not: never cut at the bottom.
            ViewThatFits(in: .vertical) {
                list
                ScrollView(showsIndicators: false) { list }
            }
        }
        .frame(width: 340)
        .background(LetterKeys(actions: Dictionary(uniqueKeysWithValues: programs.compactMap { tool in
            Self.letters[tool].map { ($0, { ToolLauncher.start(tool) }) }
        })))
        .onAppear { catalog.refresh() }
    }
    private var list: some View {
        MenuList {
            MenuRow(title: "Terminal", key: "⌘T") { run { model.newTerminal() } }
            ForEach(ready, id: \.self) { tool in
                MenuRow(title: tool.title, note: catalog.note(tool), key: Self.letters[tool] ?? "") { run { ToolLauncher.start(tool) } }
            }
            ForEach(store.settings.startablePrograms) { program in
                MenuRow(title: program.name, note: program.command) { run { ToolLauncher.start(program) } }
            }
            if !missing.isEmpty {
                if showAll {
                    MenuDivider()
                    ForEach(missing, id: \.self) { tool in
                        MenuRow(title: tool.title, note: "Kurulu Değil", key: Self.letters[tool] ?? "") { run { ToolLauncher.start(tool) } }
                    }
                } else {
                    MenuRow(title: "Diğer Programlar", note: "\(missing.count) Program Kurulabilir") { showAll = true }
                }
            }
            MenuDivider()
            MenuRow(title: "Seçeneklerle Aç", note: "Klasör, Hesap, Yetki, Model") { run { Commands.perform("newSessionOptions") } }
        }
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
            // Whole when the window is tall enough, scrolling when it is not: never cut at the bottom.
            ViewThatFits(in: .vertical) {
                items
                ScrollView(showsIndicators: false) { items }
            }
        }
        .frame(width: 320)
    }
    private var items: some View {
        MenuList {
            item("Yeni Terminal", key: "⌘T", id: "newTerminal")
            MenuDivider()
            item("Yeni Görünüm", note: "Dosyalar, Düzenleyici, Not", id: "newView")
            item("Pano", note: "Kartlar, Üyeler, Son Tarihler", id: "board")
            item("Konuşarak Yaz", note: "Konuşun, Yazıya Dönsün", key: "⌃⌘ Basılı", id: "voice")
            item("Geçmiş Konuşmalar", note: "Açın, Sürdürün", id: "history")
            item("Uzak Sunucu", note: "SSH İle Proje Açın", id: "remote")
            item("Değişiklikler Ve Git", note: "Hazırla, Commit, Push", id: "changes")
            item("Ekibini Kur", note: "Birkaç Claude Code Birlikte Çalışır", id: "team")
            item("Hesaplar", note: "Claude Code, Codex, Antigravity Girişleri", id: "accounts")
            item("Telefonu Bağla", note: "Bu Terminali Telefonda Açın", id: "phone")
            MenuDivider()
            item("Ayarlar", key: "⌘,", id: "settings")
            item("Tüm Komutlar", key: "⌘K", id: "palette")
        }
    }
    private func item(_ title: String, note: String = "", key: String = "", id: String) -> some View {
        MenuRow(title: title, note: note, key: key) {
            AppModel.shared.overlay = nil
            DispatchQueue.main.async { Commands.perform(id) }
        }
    }
}
