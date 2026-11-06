import AppKit
import EntermCore
import SwiftUI

// What the canvas holds besides terminals, and how it is arranged: projects, views, groups, saved layouts.

enum ItemKind: String, Codable, CaseIterable {
    case note, browser, web, whiteboard, files, video, simulator, game

    var title: String {
        switch self {
        case .note: return "Not"
        case .browser: return "Tarayıcı"
        case .web: return "Web Sayfası"
        case .video: return "Video"
        case .game: return "Enter Koşusu"
        case .whiteboard: return "Beyaz Tahta"
        case .files: return "Dosyalar"
        case .simulator: return "iOS Simülatörü"
        }
    }
    var icon: String {
        switch self {
        case .note: return "note.text"
        case .browser: return "safari"
        case .web: return "globe"
        case .video: return "play.rectangle"
        case .game: return "gamecontroller"
        case .whiteboard: return "scribble"
        case .files: return "folder"
        case .simulator: return "iphone"
        }
    }
}

/// A view on the canvas. It exists only while it is open and costs nothing until then.
struct CanvasItem: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var kind: ItemKind
    var title: String
    var text = ""
    var project: String?
}

struct CanvasGroup: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var colorIndex = 0
    var members: [String] = []
}

struct SavedLayout: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var positions: [String: CGPoint]
    var sizes: [String: CGSize]
}

struct LayoutSnapshot {
    let positions: [String: CGPoint]
    let sizes: [String: CGSize]
    let freeLayout: Bool
}

/// What the app remembers between launches. Everything else lives in the session service.
struct WindowState: Codable {
    var mode: ViewMode = .single
    var positions: [String: CGPoint] = [:]
    var sizes: [String: CGSize] = [:]
    var freeLayout = false
    var items: [CanvasItem] = []
    var groups: [CanvasGroup] = []
    var layouts: [SavedLayout] = []
    var projects: [String: String] = [:]
    var activeProject: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WindowState()
        mode = try c.decodeIfPresent(ViewMode.self, forKey: .mode) ?? d.mode
        positions = try c.decodeIfPresent([String: CGPoint].self, forKey: .positions) ?? d.positions
        sizes = try c.decodeIfPresent([String: CGSize].self, forKey: .sizes) ?? d.sizes
        freeLayout = try c.decodeIfPresent(Bool.self, forKey: .freeLayout) ?? d.freeLayout
        items = try c.decodeIfPresent([CanvasItem].self, forKey: .items) ?? d.items
        groups = try c.decodeIfPresent([CanvasGroup].self, forKey: .groups) ?? d.groups
        layouts = try c.decodeIfPresent([SavedLayout].self, forKey: .layouts) ?? d.layouts
        projects = try c.decodeIfPresent([String: String].self, forKey: .projects) ?? d.projects
        activeProject = try c.decodeIfPresent(String.self, forKey: .activeProject)
    }
}

extension AppModel {
    // MARK: Projects

    static func projectName(for folder: String) -> String {
        if folder == NSHomeDirectory() || folder.isEmpty { return "Ana Klasör" }
        return (folder as NSString).lastPathComponent
    }

    func project(of info: SessionInfo) -> String {
        if let saved = state.projects[info.id] { return saved }
        let name = Self.projectName(for: info.cwd)
        state.projects[info.id] = name
        return name
    }

    /// In the order they were opened. A project is whatever has something open in it.
    var projectNames: [String] {
        var names: [String] = []
        for info in sessions {
            let name = project(of: info)
            if !names.contains(name) { names.append(name) }
        }
        for item in state.items {
            if let name = item.project, !names.contains(name) { names.append(name) }
        }
        return names
    }

    var visibleItems: [CanvasItem] {
        guard !sessions.isEmpty || !state.items.isEmpty else { return [] }
        return state.items.filter { $0.project == nil || activeProject == nil || $0.project == activeProject }
    }

    /// How many boxes share the surface right now.
    var tileCount: Int { visibleSessions.count + visibleItems.count }

    func switchProject(_ name: String) {
        activeProject = name
        showHome = false
        maximized = nil
        state.activeProject = name
        if let info = visibleSessions.first(where: { $0.number == lastFocus[name] }) ?? visibleSessions.first {
            setFocus(info.number)
        } else {
            focused = nil
        }
        if tileCount > 1, mode == .single { mode = .canvas }
        onLayoutChange?()
        saveState()
    }

    func showHomeScreen() {
        showHome = true
        onLayoutChange?()
    }

    func closeProject(_ name: String) {
        let members = sessions.filter { project(of: $0) == name }
        state.items.removeAll { $0.project == name }
        for info in members { close(info.number) }
        if activeProject == name {
            activeProject = projectNames.first
            state.activeProject = activeProject
            if let next = activeProject { switchProject(next) }
        }
        onLayoutChange?()
        saveState()
    }

    /// Opening something that belongs to another project takes the person there.
    func followFocus(_ number: UInt32?) {
        guard let number, let info = sessions.first(where: { $0.number == number }) else { return }
        let name = project(of: info)
        lastFocus[name] = number
        if activeProject != name {
            activeProject = name
            state.activeProject = name
        }
    }

    func assignProject(_ info: SessionInfo) {
        guard state.projects[info.id] == nil else { return }
        let name = startingFromHome ? Self.projectName(for: info.cwd) : (activeProject ?? Self.projectName(for: info.cwd))
        state.projects[info.id] = name
        startingFromHome = false
        showHome = false
        activeProject = name
        state.activeProject = name
    }

    // MARK: Views on the canvas

    func addItem(_ kind: ItemKind) {
        if kind == .browser, let open = state.items.first(where: { $0.kind == .browser }) {
            if let name = open.project { switchProject(name) }
            return
        }
        pushLayoutUndo()
        state.items.append(CanvasItem(kind: kind, title: kind.title, project: activeProject ?? focusedInfo.map(project(of:))))
        if tileCount > 1, mode == .single { mode = .canvas }
        maximized = nil
        onLayoutChange?()
        saveState()
    }

    func removeItem(_ id: String) {
        if state.items.first(where: { $0.id == id })?.kind == .browser { BrowserCenter.shared.close() }
        state.items.removeAll { $0.id == id }
        state.positions[id] = nil
        state.sizes[id] = nil
        if tileCount <= 1, !sessions.isEmpty { mode = .single }
        onLayoutChange?()
        saveState()
    }

    func updateItem(_ id: String, text: String) {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        state.items[index].text = text
        saveState()
    }

    // MARK: Layout history

    private var snapshot: LayoutSnapshot { LayoutSnapshot(positions: state.positions, sizes: state.sizes, freeLayout: state.freeLayout) }

    func pushLayoutUndo() {
        layoutUndo.append(snapshot)
        if layoutUndo.count > 50 { layoutUndo.removeFirst() }
        layoutRedo.removeAll()
    }

    private func restore(_ snapshot: LayoutSnapshot) {
        state.positions = snapshot.positions
        state.sizes = snapshot.sizes
        state.freeLayout = snapshot.freeLayout
        onLayoutChange?()
        saveState()
    }

    func undoLayout() {
        guard let last = layoutUndo.popLast() else {
            hint = "Geri Alınacak Düzen Yok"
            return
        }
        layoutRedo.append(snapshot)
        restore(last)
    }

    func redoLayout() {
        guard let last = layoutRedo.popLast() else {
            hint = "Yinelenecek Düzen Yok"
            return
        }
        layoutUndo.append(snapshot)
        restore(last)
    }

    func saveLayout(named name: String) {
        state.layouts.removeAll { $0.name == name }
        state.layouts.append(SavedLayout(name: name, positions: state.positions, sizes: state.sizes))
        saveState()
        hint = "Yerleşim Kaydedildi: \(name)"
    }

    func applyLayout(_ layout: SavedLayout) {
        pushLayoutUndo()
        state.positions.merge(layout.positions) { _, new in new }
        state.sizes.merge(layout.sizes) { _, new in new }
        state.freeLayout = true
        onLayoutChange?()
        saveState()
    }

    // MARK: Groups

    func addToNewGroup(_ id: String, name: String) {
        var group = CanvasGroup(name: name, colorIndex: state.groups.count)
        group.members = [id]
        removeFromGroups(id)
        state.groups.append(group)
        onLayoutChange?()
        saveState()
    }

    func addToGroup(_ id: String, group groupID: String) {
        removeFromGroups(id)
        if let index = state.groups.firstIndex(where: { $0.id == groupID }) { state.groups[index].members.append(id) }
        onLayoutChange?()
        saveState()
    }

    func removeFromGroups(_ id: String) {
        for index in state.groups.indices { state.groups[index].members.removeAll { $0 == id } }
        state.groups.removeAll { $0.members.isEmpty }
        onLayoutChange?()
        saveState()
    }

    func group(of id: String) -> CanvasGroup? { state.groups.first { $0.members.contains(id) } }

    // MARK: Reopening

    func reopenLast() {
        guard let info = closedSessions.popLast() else {
            hint = "Yeniden Açılacak Oturum Yok"
            return
        }
        Restore.start(info)
    }

    // MARK: Asking

    func ask(title: String, placeholder: String = "", initial: String = "", confirm: String = "Tamam", action: @escaping (String) -> Void) {
        inputRequest = InputRequest(title: title, placeholder: placeholder, initial: initial, confirm: confirm, action: action)
        overlay = .input
    }

    /// The main button wears the accent. Red only for what ends running work and cannot be undone: `danger: true`.
    func confirm(title: String, detail: String, action title2: String, danger: Bool = false, perform: @escaping () -> Void) {
        confirmRequest = ConfirmRequest(title: title, detail: detail, confirm: title2, danger: danger, action: perform)
        overlay = .confirm
    }
}

struct InputRequest {
    let title: String
    let placeholder: String
    let initial: String
    let confirm: String
    let action: (String) -> Void
}

struct ConfirmRequest {
    let title: String
    let detail: String
    let confirm: String
    let danger: Bool
    let action: () -> Void
}

struct InputDialog: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @State private var text = ""
    @FocusState private var focus: Bool
    var body: some View {
        if let request = model.inputRequest {
            Panel {
                PanelHeader(title: request.title)
                TextField("", text: $text, prompt: Text(request.placeholder).foregroundColor(Color(Theme.palette.text3)))
                    .textFieldStyle(.plain)
                    .font(Theme.uiFont(.body))
                    .foregroundColor(Color(Theme.palette.text1))
                    .focused($focus)
                    .onSubmit { commit(request) }
                    // EntermField's numbers; it is built here only because this field takes the focus on opening.
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color(Theme.palette.terminal))
                    .cornerRadius(Theme.cornerControl)
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerControl).stroke(focus ? Color(Theme.palette.need).opacity(0.7) : Color(Theme.palette.hair2)))
                    .padding(20)
                DialogButtons {
                    Btn("Vazgeç", kind: .plain, key: "Esc") { model.overlay = nil }
                    Btn(request.confirm, kind: .primary, key: "⏎") { commit(request) }
                }
            }
            .frame(width: 440)
            .onAppear {
                text = request.initial
                focus = true
            }
        }
    }

    private func commit(_ request: InputRequest) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        model.overlay = nil
        request.action(value)
    }
}

struct ConfirmDialog: View {
    @ObservedObject var model = AppModel.shared
    var body: some View {
        if let request = model.confirmRequest {
            Panel {
                PanelHeader(title: request.title)
                Dim(request.detail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20)
                DialogButtons {
                    Btn("Vazgeç", kind: .plain, key: "Esc") { model.overlay = nil }
                    Btn(request.confirm, kind: request.danger ? .danger : .primary) {
                        model.overlay = nil
                        request.action()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .frame(width: 440)
        }
    }
}

// MARK: Menus

/// A menu row with its action in place.
final class ActionMenuItem: NSMenuItem {
    private let run: () -> Void
    init(_ title: String, key: String = "", enabled: Bool = true, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        isEnabled = enabled
    }
    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { run() }
}

enum CanvasMenus {
    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    private static func programItems(cwd: String? = nil) -> [NSMenuItem] {
        let settings = SettingsStore.shared.settings
        var items = ToolKind.programs.filter { !settings.hiddenTools.contains($0.rawValue) }.map { tool in
            ActionMenuItem(tool.title) { ToolLauncher.start(tool, cwd: cwd) } as NSMenuItem
        }
        for program in settings.startablePrograms {
            items.append(ActionMenuItem(program.name) { ToolLauncher.start(program, cwd: cwd) })
        }
        return items
    }

    /// The empty part of the canvas.
    static func canvas() -> NSMenu {
        let model = AppModel.shared
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem("Yeni Terminal") { model.newTerminal() })
        menu.addItem(submenu("Yeni Program", programItems()))
        menu.addItem(submenu("Yeni Görünüm", ItemKind.allCases.map { kind in ActionMenuItem(kind.title) { model.addItem(kind) } }))
        menu.addItem(submenu("Düzenle", [
            ActionMenuItem("Ekip Kur") { Commands.perform("team") },
            ActionMenuItem("Worktree Aç") { Commands.perform("worktree") },
            ActionMenuItem("Zamanlayıcı") { Commands.perform("scheduler") },
            ActionMenuItem("Pano") { Commands.perform("board") },
        ]))
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Tümünü Sığdır") { Commands.perform("fit") })
        menu.addItem(ActionMenuItem("Kutuları Diz") { Commands.perform("arrange") })
        menu.addItem(ActionMenuItem("Düzeni Geri Al", enabled: !model.layoutUndo.isEmpty) { model.undoLayout() })
        menu.addItem(ActionMenuItem("Düzeni Yinele", enabled: !model.layoutRedo.isEmpty) { model.redoLayout() })
        var layouts: [NSMenuItem] = [ActionMenuItem("Bu Yerleşimi Kaydet") { Commands.perform("saveLayout") }]
        if !model.state.layouts.isEmpty { layouts.append(.separator()) }
        layouts += model.state.layouts.map { layout in ActionMenuItem(layout.name) { model.applyLayout(layout) } }
        menu.addItem(submenu("Yerleşimler", layouts))
        return menu
    }

    /// A session's tab, or the terminal itself.
    static func session(_ info: SessionInfo) -> NSMenu {
        let model = AppModel.shared
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem("Yeniden Adlandır") {
            model.ask(title: "Oturumun Adı", placeholder: info.tool.title, initial: info.name, confirm: "Adlandır") { model.rename(info.number, $0) }
        })
        if model.tileCount > 1 {
            menu.addItem(ActionMenuItem(model.maximized == info.number ? "Tümünü Gör" : "Tam Ekran") {
                model.setFocus(info.number)
                model.toggleMaximize()
            })
        }
        if info.tool == .claude || info.tool == .codex {
            menu.addItem(ActionMenuItem(model.chatSessions.contains(info.number) ? "Terminal Görünümü" : "Sohbet Görünümü") { model.toggleChat(info.number) })
        }
        menu.addItem(.separator())
        var groupItems: [NSMenuItem] = [ActionMenuItem("Yeni Grup") {
            model.ask(title: "Grubun Adı", placeholder: "Örnek: Ödeme", confirm: "Oluştur") { model.addToNewGroup(info.id, name: $0) }
        }]
        for group in model.state.groups { groupItems.append(ActionMenuItem(group.name) { model.addToGroup(info.id, group: group.id) }) }
        if model.group(of: info.id) != nil {
            groupItems.append(.separator())
            groupItems.append(ActionMenuItem("Gruptan Çıkar") { model.removeFromGroups(info.id) })
        }
        menu.addItem(submenu("Gruba Ekle", groupItems))
        if model.tileCount > 1 {
            menu.addItem(submenu("Yerleştir", [
                ActionMenuItem("Sol Yarı") { model.onSnap?(info.number, .left) },
                ActionMenuItem("Sağ Yarı") { model.onSnap?(info.number, .right) },
                ActionMenuItem("Üst Yarı") { model.onSnap?(info.number, .top) },
                ActionMenuItem("Alt Yarı") { model.onSnap?(info.number, .bottom) },
            ]))
            let others = model.visibleSessions.filter { $0.number != info.number }
            menu.addItem(submenu("Bağla", others.map { other in
                ActionMenuItem(model.name(for: other)) { model.overlay = .linkPermission(from: info.number, to: other.number) }
            }))
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Aynısından Aç") {
            if info.tool == .custom, let program = SettingsStore.shared.settings.customPrograms.first(where: { $0.name == info.name }) {
                ToolLauncher.start(program, cwd: info.cwd)
            } else if info.tool.command == nil {
                model.newTerminal(cwd: info.cwd)
            } else {
                ToolLauncher.start(info.tool, cwd: info.cwd)
            }
        })
        if info.tool == .terminal {
            menu.addItem(ActionMenuItem("Kopyala") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) })
            menu.addItem(ActionMenuItem("Yapıştır") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) })
        }
        menu.addItem(ActionMenuItem("Kapat", key: "") { model.close(info.number) })
        return menu
    }
}

enum SnapZone { case left, right, top, bottom }

// MARK: View boxes

/// A view on the canvas, in the same tabbed frame as a terminal.
final class ItemBox: NSView {
    let itemID: String
    weak var canvas: CanvasView?
    private let host: NSHostingView<ItemFrame>

    init(item: CanvasItem) {
        itemID = item.id
        host = NSHostingView(rootView: ItemFrame(item: item))
        super.init(frame: .zero)
        host.safeAreaRegions = []
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        host.frame = bounds
    }
}

struct ItemFrame: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let item: CanvasItem
    @State private var dragStart: NSPoint?
    @State private var sizeStart: NSRect?
    var body: some View {
        let palette = Theme.palette
        // The tab overlaps the box by its line, so the two share one outline.
        VStack(alignment: .leading, spacing: -1) {
            HStack(spacing: 8) {
                // Title at 10 + 14 + 6 = 30, where a terminal box's tab puts it.
                HStack(spacing: 6) {
                    Symbol(item.kind.icon, color: palette.text2, size: 14)
                    T(item.title, bold: true).lineLimit(1)
                }
                TabCloseButton { AppModel.shared.removeItem(item.id) }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 30)
            .background(Color(palette.surface1))
            .cornerRadius(Theme.cornerCard, corners: [.topLeft, .topRight])
            .overlay(TabOutline(radius: Theme.cornerCard).stroke(Color(palette.hair2), lineWidth: 1))
            .zIndex(1)
            .gesture(DragGesture(coordinateSpace: .global).onChanged { value in
                guard let canvas = canvas else { return }
                if dragStart == nil {
                    dragStart = canvas.origin(ofItem: item.id)
                    AppModel.shared.pushLayoutUndo()
                }
                guard let dragStart else { return }
                canvas.moveItem(item.id, to: NSPoint(x: dragStart.x + value.translation.width, y: dragStart.y + value.translation.height))
            }.onEnded { _ in dragStart = nil })
            ZStack(alignment: .bottomTrailing) {
                ItemContent(item: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9))
                    .rotationEffect(.degrees(90))
                    .foregroundColor(Color(palette.text3))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active: NSCursor.resizeCorner.set()
                        // While shrinking stops at its least size the pointer leaves the grip: the drag keeps the arrow.
                        case .ended: if sizeStart == nil { NSCursor.arrow.set() }
                        }
                    }
                    .gesture(DragGesture(coordinateSpace: .global).onChanged { value in
                        guard let canvas = canvas else { return }
                        if sizeStart == nil {
                            sizeStart = canvas.frame(ofItem: item.id)
                            AppModel.shared.pushLayoutUndo()
                        }
                        guard let sizeStart else { return }
                        canvas.resizeItem(item.id, to: NSSize(width: sizeStart.width + value.translation.width, height: sizeStart.height + value.translation.height))
                    }.onEnded { _ in
                        sizeStart = nil
                        NSCursor.arrow.set()
                    })
            }
            .background(Color(palette.surface0))
            .cornerRadius(Theme.cornerCard, corners: [.topRight, .bottomLeft, .bottomRight])
            .overlay(SomeCorners(radius: Theme.cornerCard, corners: [.topRight, .bottomLeft, .bottomRight]).stroke(Color(palette.hair2), lineWidth: 1).padding(0.5))
        }
        .clipped()
    }

    private var canvas: CanvasView? {
        (NSApp.windows.first { $0.contentView is RootView }?.contentView as? RootView)?.canvas
    }
}

/// The x on a view box's tab. 18 in the 30 tab leaves 6 above, below and after it.
private struct TabCloseButton: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            Symbol("xmark", color: hovering ? palette.text1 : palette.text3, size: 10)
                .frame(width: 18, height: 18)
                .background(hovering ? Color(palette.fill) : .clear)
                .cornerRadius(Theme.cornerControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
        .help("Kapat")
    }
}

private struct ItemContent: View {
    let item: CanvasItem
    var body: some View {
        Group {
            switch item.kind {
            case .note: StickyNote(item: item)
            case .browser: BrowserPage().padding(12)
            case .web: WebBox(item: item)
            case .video: VideoBox(item: item)
            case .game: RunnerGame()
            case .whiteboard: WhiteboardPage().padding(12)
            case .files: ScrollView { FilesPage().padding(12) }
            case .simulator: SimulatorPage().padding(12)
            }
        }
        .environment(\.embeddedPage, true)
        .environment(\.boxedPage, true)
    }
}

/// A note on the canvas. Its words can go to the session in focus with one click.
private struct StickyNote: View {
    let item: CanvasItem
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .onChange(of: text) { AppModel.shared.updateItem(item.id, text: $0) }
                .overlay(alignment: .topLeading) {
                    if text.isEmpty { Dim("Bir not yazın").padding(.leading, 5).allowsHitTesting(false) }
                }
            HStack {
                Spacer()
                Btn("Odaktaki Oturuma Yaz", kind: .plain, icon: "arrow.turn.down.left") {
                    AppModel.shared.focusedHost?.type(text)
                    AppModel.shared.refocusTerminal()
                }
                .disabled(text.isEmpty || AppModel.shared.focusedHost == nil)
            }
            // Clears the 18 resize grip and no more: 12 + 6.
            .padding(.trailing, 6)
        }
        .padding(12)
        .onAppear { text = item.text }
    }
}

// MARK: Group frames

/// A frame around the boxes of a group, under them. Only its label takes the mouse.
final class GroupFrameView: NSView {
    private(set) var group: CanvasGroup
    weak var canvas: CanvasView?
    private var dragStart: NSPoint?
    private static let colors: [NSColor] = [Theme.palette.g1, Theme.palette.add, Theme.palette.g2, Theme.palette.limit]

    init(group: CanvasGroup) {
        self.group = group
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func update(_ group: CanvasGroup) {
        self.group = group
        needsDisplay = true
    }

    private var color: NSColor { Self.colors[group.colorIndex % Self.colors.count] }
    private var labelRect: NSRect {
        let width = (group.name as NSString).size(withAttributes: [.font: Theme.ui(.secondary, weight: .semibold)]).width + 16
        return NSRect(x: 12, y: 0, width: width, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 10), xRadius: Theme.cornerCard, yRadius: Theme.cornerCard)
        frame.lineWidth = 1
        color.withAlphaComponent(0.5).setStroke()
        frame.stroke()
        color.withAlphaComponent(0.03).setFill()
        frame.fill()
        let label = NSBezierPath(roundedRect: labelRect, xRadius: Theme.cornerControl, yRadius: Theme.cornerControl)
        Theme.palette.surface0.setFill()
        label.fill()
        color.withAlphaComponent(0.5).setStroke()
        label.stroke()
        (group.name as NSString).draw(at: NSPoint(x: labelRect.minX + 8, y: labelRect.minY + 3), withAttributes: [
            .font: Theme.ui(.secondary, weight: .semibold), .foregroundColor: color,
        ])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return labelRect.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        AppModel.shared.pushLayoutUndo()
        canvas?.freezeLayout()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        canvas?.moveGroup(group, by: NSPoint(x: event.locationInWindow.x - start.x, y: start.y - event.locationInWindow.y))
        dragStart = event.locationInWindow
    }

    override func mouseUp(with event: NSEvent) { dragStart = nil }

    override func menu(for event: NSEvent) -> NSMenu? {
        let model = AppModel.shared
        let id = group.id
        let name = group.name
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem("Yeniden Adlandır") {
            model.ask(title: "Grubun Adı", initial: name, confirm: "Adlandır") { value in
                if let index = model.state.groups.firstIndex(where: { $0.id == id }) { model.state.groups[index].name = value }
                model.onLayoutChange?()
                model.saveState()
            }
        })
        menu.addItem(ActionMenuItem("Grubu Dağıt") {
            model.state.groups.removeAll { $0.id == id }
            model.onLayoutChange?()
            model.saveState()
        })
        return menu
    }
}

// MARK: Worktrees

enum WorktreeActions {
    /// A new branch in its own folder beside the project, with the default program open in it, framed as a group.
    static func create(branch: String) {
        let model = AppModel.shared
        let runner = model.currentRunner
        guard runner.remote == nil else {
            model.hint = "Worktree Yalnız Bu Bilgisayardaki Projede Açılır"
            return
        }
        let root = Git.run(["rev-parse", "--show-toplevel"], runner: runner)
        guard root.ok else {
            model.hint = "Bu Klasör Bir Git Deposu Değil"
            return
        }
        let top = root.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = (top as NSString).deletingLastPathComponent + "/" + (top as NSString).lastPathComponent + ".worktrees/" + branch.replacingOccurrences(of: "/", with: "-")
        let result = Git.run(["worktree", "add", folder, "-b", branch], runner: runner)
        guard result.ok else {
            model.hint = "Worktree Açılmadı: \(result.output.prefix(120))"
            return
        }
        let settings = SettingsStore.shared.settings
        let finish: (SessionInfo) -> Void = { info in model.addToNewGroup(info.id, name: branch) }
        switch settings.defaultProgram {
        case "claude": ToolLauncher.start(.claude, cwd: folder, then: finish)
        case "codex": ToolLauncher.start(.codex, cwd: folder, then: finish)
        case "agy": ToolLauncher.start(.antigravity, cwd: folder, then: finish)
        default:
            model.create(SessionSpec(tool: .terminal, cwd: folder, rows: 30, cols: 100), then: finish)
        }
    }
}

// MARK: Rounded corners on chosen sides

struct CornerSet: OptionSet {
    let rawValue: Int
    static let topLeft = CornerSet(rawValue: 1)
    static let topRight = CornerSet(rawValue: 2)
    static let bottomLeft = CornerSet(rawValue: 4)
    static let bottomRight = CornerSet(rawValue: 8)
}

struct SomeCorners: Shape {
    let radius: CGFloat
    let corners: CornerSet
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0, tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0, br = corners.contains(.bottomRight) ? radius : 0
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tl, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

/// A tab's line: up the left, over the rounded top, down the right. The bottom is the box's own line.
struct TabOutline: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX + 0.5, right = rect.maxX - 0.5, top = rect.minY + 0.5
        path.move(to: CGPoint(x: left, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: right, y: top), radius: radius)
        path.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: rect.maxY), radius: radius)
        path.addLine(to: CGPoint(x: right, y: rect.maxY))
        return path
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: CornerSet) -> some View {
        clipShape(SomeCorners(radius: radius, corners: corners))
    }
}
