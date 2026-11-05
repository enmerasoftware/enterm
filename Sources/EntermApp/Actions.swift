import AppKit
import EntermCore

/// Every command the app has. Menus, the palette, single keys and tests all come through here.
struct Command: Identifiable {
    let id: String
    let title: String
    let key: String
    var note: String = ""
}

enum Commands {
    static let all: [Command] = [
        Command(id: "team", title: "Ekibini Kur", key: "e"),
        Command(id: "manager", title: "Yönetici Görünümü", key: "⌘⇧Y"),
        Command(id: "newSession", title: "Yeni Oturum", key: "n"),
        Command(id: "newTerminal", title: "Yeni Terminal", key: "⌘T"),
        Command(id: "newClaude", title: "Yeni Claude Code", key: ""),
        Command(id: "newCodex", title: "Yeni Codex", key: ""),
        Command(id: "newAntigravity", title: "Yeni Antigravity", key: ""),
        Command(id: "newGemini", title: "Yeni Gemini", key: ""),
        Command(id: "newOpencode", title: "Yeni opencode", key: ""),
        Command(id: "newGrok", title: "Yeni Grok", key: ""),
        Command(id: "newCopilot", title: "Yeni GitHub Copilot", key: ""),
        Command(id: "newCursor", title: "Yeni Cursor", key: ""),
        Command(id: "newProject", title: "Yeni Proje", key: "⌘⇧N"),
        Command(id: "reopen", title: "Son Kapatılanı Yeniden Aç", key: "⌘⇧T"),
        Command(id: "chat", title: "Sohbet Görünümü", key: "⌘⇧M"),
        Command(id: "maximize", title: "Seçili Kutuyu Tam Ekran Aç", key: "⌘⏎"),
        Command(id: "noteBox", title: "Tuvale Not Ekle", key: ""),
        Command(id: "browserBox", title: "Tuvale Tarayıcı Ekle", key: ""),
        Command(id: "whiteboardBox", title: "Tuvale Beyaz Tahta Ekle", key: ""),
        Command(id: "filesBox", title: "Tuvale Dosyalar Ekle", key: ""),
        Command(id: "simulatorBox", title: "Tuvale iOS Simülatörü Ekle", key: ""),
        Command(id: "worktree", title: "Worktree Aç", key: ""),
        Command(id: "saveLayout", title: "Bu Yerleşimi Kaydet", key: ""),
        Command(id: "undoLayout", title: "Düzeni Geri Al", key: "⌥⌘Z"),
        Command(id: "redoLayout", title: "Düzeni Yinele", key: "⌥⇧⌘Z"),
        Command(id: "zoneLeft", title: "Kutuyu Sol Yarıya Yerleştir", key: "⌃⌥←"),
        Command(id: "zoneRight", title: "Kutuyu Sağ Yarıya Yerleştir", key: "⌃⌥→"),
        Command(id: "zoneTop", title: "Kutuyu Üst Yarıya Yerleştir", key: "⌃⌥↑"),
        Command(id: "zoneBottom", title: "Kutuyu Alt Yarıya Yerleştir", key: "⌃⌥↓"),
        Command(id: "focusLeft", title: "Soldaki Kutuya Geç", key: "⌥⌘←"),
        Command(id: "focusRight", title: "Sağdaki Kutuya Geç", key: "⌥⌘→"),
        Command(id: "focusUp", title: "Üstteki Kutuya Geç", key: "⌥⌘↑"),
        Command(id: "focusDown", title: "Alttaki Kutuya Geç", key: "⌥⌘↓"),
        Command(id: "memory", title: "Bellek Kullanımı", key: ""),
        Command(id: "focusMode", title: "Odak Modu", key: "⌘⇧F"),
        Command(id: "lockCanvas", title: "Tuvali Kilitle Ya Da Aç", key: ""),
        Command(id: "recents", title: "Tüm Geçmiş Konuşmalar", key: ""),
        Command(id: "toggleRail", title: "Durak Hattını Göster Ya Da Gizle", key: "⌘⇧L"),
        Command(id: "webBox", title: "Tuvale Web Sayfası Ekle", key: ""),
        Command(id: "videoBox", title: "Tuvale Video Ekle", key: ""),
        Command(id: "gameBox", title: "Enter Koşusu", key: ""),
        Command(id: "details", title: "Ayrıntılar", key: "⌘I"),
        Command(id: "close", title: "Kutuyu Kapat", key: "⌘W"),
        Command(id: "inbox", title: "Onay Kutusu", key: "⌘⇧O"),
        Command(id: "board", title: "Pano", key: "⌘⇧B"),
        Command(id: "toggleCanvas", title: "Tuval Ve Sekmeler Arasında Geç", key: ""),
        Command(id: "sessionList", title: "Tüm Oturumlar", key: ""),
        Command(id: "link", title: "Kutuları Bağla", key: ""),
        Command(id: "messages", title: "Ajanlar Arası Mesaj Geçmişi", key: ""),
        Command(id: "fit", title: "Sığdır", key: "0"),
        Command(id: "zoomIn", title: "Yakınlaştır", key: "⌘="),
        Command(id: "zoomOut", title: "Uzaklaştır", key: "⌘-"),
        Command(id: "accounts", title: "Hesaplar", key: ""),
        Command(id: "settings", title: "Ayarlar", key: "⌘,"),
        Command(id: "shortcuts", title: "Tüm Kısayollar", key: "?"),
        Command(id: "power", title: "Güç Sınırı", key: ""),
        Command(id: "lowPower", title: "Düşük Güçlü Bilgisayar Aç Ya Da Kapat", key: ""),
        Command(id: "history", title: "Geçmiş Konuşmalar", key: ""),
        Command(id: "scheduler", title: "Zamanlayıcı", key: ""),
        Command(id: "files", title: "Dosya Gezgini", key: ""),
        Command(id: "run", title: "Çalıştır", key: ""),
        Command(id: "whiteboard", title: "Beyaz Tahta", key: ""),
        Command(id: "simulator", title: "iOS Simülatörü", key: ""),
        Command(id: "welcome", title: "Kurulum Turu", key: ""),
        Command(id: "uninstall", title: "Enterm'i Kaldır", key: ""),
        Command(id: "newView", title: "Yeni Görünüm", key: ""),
        Command(id: "voice", title: "Konuşarak Yaz", key: "⌃⌘ Basılı"),
        Command(id: "remote", title: "Uzak Sunucu", key: ""),
        Command(id: "phone", title: "Telefonu Bağla", key: ""),
        Command(id: "stop", title: "Durdur", key: "⌘."),
        Command(id: "changes", title: "Değişiklikler Ve Git", key: ""),
        Command(id: "browser", title: "Tarayıcı", key: "⌘⇧D"),
    ]

    /// What can change while the app runs: open sessions, projects and saved layouts.
    static var dynamic: [Command] {
        let model = AppModel.shared
        var list: [Command] = []
        for info in model.sessions where info.number != model.focused {
            list.append(Command(id: "goto:\(info.number)", title: "Git: \(model.name(for: info))", key: ""))
        }
        for name in model.projectNames where name != model.activeProject {
            list.append(Command(id: "project:\(name)", title: "Proje: \(name)", key: ""))
        }
        for layout in model.state.layouts {
            list.append(Command(id: "layout:\(layout.id)", title: "Yerleşim: \(layout.name)", key: ""))
        }
        for program in SettingsStore.shared.settings.customPrograms {
            list.append(Command(id: "custom:\(program.id)", title: "Yeni \(program.name)", key: ""))
        }
        return list
    }

    static func perform(_ id: String) {
        let model = AppModel.shared
        if id.hasPrefix("goto:"), let number = UInt32(id.dropFirst(5)) {
            model.setFocus(number)
            model.onLayoutChange?()
            return
        }
        if id.hasPrefix("project:") {
            model.switchProject(String(id.dropFirst(8)))
            return
        }
        if id.hasPrefix("layout:") {
            if let layout = model.state.layouts.first(where: { $0.id == id.dropFirst(7) }) { model.applyLayout(layout) }
            return
        }
        if id.hasPrefix("custom:") {
            if let program = SettingsStore.shared.settings.customPrograms.first(where: { $0.id == id.dropFirst(7) }) { ToolLauncher.start(program) }
            return
        }
        switch id {
        case "newProject": model.showHomeScreen()
        case "reopen": model.reopenLast()
        case "chat":
            if let info = model.focusedInfo, info.tool == .claude || info.tool == .codex {
                model.toggleChat(info.number)
            } else {
                model.hint = "Sohbet Görünümü Claude Code Ve Codex'te Var"
            }
        case "noteBox": model.addItem(.note)
        case "browserBox": model.addItem(.browser)
        case "whiteboardBox": model.addItem(.whiteboard)
        case "filesBox": model.addItem(.files)
        case "simulatorBox": model.addItem(.simulator)
        case "worktree":
            model.ask(title: "Yeni Worktree", placeholder: "Dal adı, örnek: odeme-duzeltme", confirm: "Aç") { WorktreeActions.create(branch: $0) }
        case "saveLayout":
            model.ask(title: "Yerleşimin Adı", placeholder: "Örnek: Geliştirme", confirm: "Kaydet") { model.saveLayout(named: $0) }
        case "undoLayout": model.undoLayout()
        case "redoLayout": model.redoLayout()
        case "zoneLeft": if let number = model.focused { model.onSnap?(number, .left) }
        case "zoneRight": if let number = model.focused { model.onSnap?(number, .right) }
        case "zoneTop": if let number = model.focused { model.onSnap?(number, .top) }
        case "zoneBottom": if let number = model.focused { model.onSnap?(number, .bottom) }
        case "focusLeft": model.onMoveFocus?(.left)
        case "focusRight": model.onMoveFocus?(.right)
        case "focusUp": model.onMoveFocus?(.top)
        case "focusDown": model.onMoveFocus?(.bottom)
        case "memory": model.overlay = model.overlay == .memory ? nil : .memory
        case "focusMode":
            model.focusMode.toggle()
            if model.focusMode, model.tileCount > 1 { model.maximized = model.focused }
            if !model.focusMode { model.maximized = nil }
            if model.focusMode { model.hint = "Odak Modu · ⌘⇧F Çıkar" }
            model.onLayoutChange?()
            model.onFocusChange?()
        case "lockCanvas":
            model.canvasLocked.toggle()
            model.hint = model.canvasLocked ? "Tuval Kilitli: Kutular Taşınmaz" : "Tuval Açık"
        case "recents": model.page = .recents
        case "toggleRail":
            SettingsStore.shared.settings.showRail.toggle()
            model.onLayoutChange?()
        case "webBox": model.addItem(.web)
        case "videoBox": model.addItem(.video)
        case "gameBox": model.addItem(.game)
        case "newTerminal": model.newTerminal()
        case "newSession": model.overlay = .newSession
        case "newClaude": ToolLauncher.start(.claude)
        case "newCodex": ToolLauncher.start(.codex)
        case "newAntigravity": ToolLauncher.start(.antigravity)
        case "newGemini": ToolLauncher.start(.gemini)
        case "newOpencode": ToolLauncher.start(.opencode)
        case "newGrok": ToolLauncher.start(.grok)
        case "newCopilot": ToolLauncher.start(.copilot)
        case "newCursor": ToolLauncher.start(.cursor)
        case "newSessionOptions": model.overlay = .newSessionOptions
        case "palette": model.overlay = model.overlay == .palette ? nil : .palette
        case "menu": model.overlay = model.overlay == .menu ? nil : .menu
        case "maximize": model.toggleMaximize()
        case "details": model.detailsOpen.toggle()
        case "close": model.closeFocused()
        case "next": model.focusNext(1)
        case "previous": model.focusNext(-1)
        case "stop": model.interrupt()
        case "toggleCanvas": model.toggleCanvas()
        case "fit": model.fitCanvas?()
        case "zoomIn": model.setZoom(model.zoom + 0.1)
        case "zoomOut": model.setZoom(model.zoom - 0.1)
        case "settings": model.page = .settings(.appearance)
        case "shortcuts": model.page = .settings(.shortcuts)
        case "power": model.page = .settings(.power)
        case "lowPower": PowerCenter.shared.settings.lowPower.toggle()
        case "accounts": model.page = .accounts
        case "inbox": model.page = .inbox
        case "board": model.page = .board
        case "team": model.page = .team
        case "manager": model.page = .manager
        case "welcome": model.page = .welcome
        case "history": model.page = .history
        case "newView": model.page = .newView
        case "sessionList": model.page = .sessionList
        case "remote": model.page = .remote
        case "phone": model.page = .phone
        case "voice": model.page = .settings(.voice)
        case "escape":
            if model.overlay != nil { model.overlay = nil } else if model.page != nil { model.goBack() } else { model.notFound = nil }
        case "link":
            model.detailTab = 1
            model.detailsOpen = true
        case "messages": model.page = .messages
        case "scheduler": model.page = .scheduler
        case "run": model.page = .run
        case "files": model.page = .files
        case "whiteboard": model.page = .whiteboard
        case "simulator": model.page = .simulator
        case "uninstall": model.page = .uninstall
        case "approveFirst":
            if let request = model.sessions.compactMap(\.pendingApproval).first { Approvals.decide(id: request.id, decision: "allow") }
        case "denyFirst":
            if let request = model.sessions.compactMap(\.pendingApproval).first { Approvals.decide(id: request.id, decision: "deny") }
        case "changes": model.page = .changes
        case "browser":
            if model.page == .browser, BrowserCenter.shared.agentName != nil {
                BrowserCenter.shared.userHasControl.toggle()
            } else {
                model.page = .browser
            }
        default: break
        }
        model.refocusTerminal()
    }
}

/// Starts a tool the way the user would type it, so the program runs unchanged.
enum ToolLauncher {
    /// A program the user added: a plain terminal that starts it, watched like the others.
    static func start(_ program: CustomProgram, cwd: String? = nil) {
        var spec = SessionSpec(name: program.name, tool: .custom, cwd: cwd ?? AppModel.shared.focusedInfo?.cwd, rows: 30, cols: 100)
        var env = program.environment
        env["ENTERM_STARTUP"] = program.startLine
        spec.env = env
        AppModel.shared.create(spec)
    }

    static func start(_ tool: ToolKind, cwd: String? = nil, name: String? = nil, accountID: String? = nil, extraArguments: String = "", group: String? = nil, plan: ModelPlan? = nil, then: ((SessionInfo) -> Void)? = nil) {
        guard let command = tool.command else {
            AppModel.shared.newTerminal(cwd: cwd)
            return
        }
        // Nothing starts for a program that is not there. The user sees why, and the command that fixes it.
        ToolCatalog.shared.refresh()
        if ToolCatalog.shared.isMissing(tool) {
            AppModel.shared.overlay = .installTool(tool)
            return
        }
        var spec = SessionSpec(name: name, tool: tool, cwd: cwd ?? AppModel.shared.focusedInfo?.cwd, rows: 30, cols: 100, group: group, accountID: accountID)
        var env = AccountStore.shared.environment(for: accountID)
        let resolvedPlan = plan ?? SettingsStore.shared.settings.defaultPlan
        if tool == .claude {
            env["ENTERM_MODEL"] = resolvedPlan.main
            env["ENTERM_EFFORT"] = resolvedPlan.mainEffort
            env["CLAUDE_CODE_SUBAGENT_MODEL"] = resolvedPlan.subagents
            if resolvedPlan.useAdvisor { env["ENTERM_ADVISOR"] = resolvedPlan.advisor }
        }
        var start = ToolCatalog.shared.startCommand(tool, command: command)
        if tool == .claude, accountID == nil, let gateway = Gateway.claudeLaunch() {
            env.merge(gateway.env) { _, new in new }
            start = gateway.prefix + start
        }
        env["ENTERM_STARTUP"] = extraArguments.isEmpty ? start : "\(start) \(extraArguments)"
        spec.env = env
        if let reason = PowerCenter.shared.blockReason() {
            PowerCenter.shared.enqueue(spec, reason: reason, then: then)
            AppModel.shared.hint = "◷ Sırada: \(reason). Çalışan iş durmadı."
            return
        }
        AppModel.shared.create(spec, then: then)
    }
}
