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
        Command(id: "maximize", title: "Seçili Kutuyu Tam Ekran Aç", key: "⌘⏎"),
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
        Command(id: "newView", title: "Yeni Görünüm", key: ""),
        Command(id: "voice", title: "Konuşarak Yaz", key: "⌃⌘ Basılı"),
        Command(id: "remote", title: "Uzak Sunucu", key: ""),
        Command(id: "phone", title: "Telefonu Bağla", key: ""),
        Command(id: "stop", title: "Durdur", key: "⌘."),
        Command(id: "changes", title: "Değişiklikler Ve Git", key: ""),
        Command(id: "browser", title: "Tarayıcı", key: "⌘⇧D"),
    ]

    static func perform(_ id: String) {
        let model = AppModel.shared
        switch id {
        case "newTerminal": model.newTerminal()
        case "newSession": model.overlay = .newSession
        case "newClaude": ToolLauncher.start(.claude)
        case "newCodex": ToolLauncher.start(.codex)
        case "newAntigravity": ToolLauncher.start(.antigravity)
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
        case "history": model.page = .history
        case "newView": model.page = .newView
        case "sessionList": model.page = .sessionList
        case "remote": model.page = .remote
        case "phone": model.page = .phone
        case "voice": model.page = .settings(.voice)
        case "escape":
            if model.overlay != nil { model.overlay = nil } else if model.page != nil { model.page = nil } else { model.notFound = nil }
        case "link":
            model.detailTab = 1
            model.detailsOpen = true
        case "messages": model.page = .messages
        case "approveFirst":
            if let request = model.sessions.compactMap(\.pendingApproval).first { Approvals.decide(id: request.id, decision: "allow") }
        case "denyFirst":
            if let request = model.sessions.compactMap(\.pendingApproval).first { Approvals.decide(id: request.id, decision: "deny") }
        case "changes": model.page = .changes
        case "browser": model.page = .browser
        default: break
        }
        model.refocusTerminal()
    }
}

/// Starts a tool the way the user would type it, so the program runs unchanged.
enum ToolLauncher {
    static func start(_ tool: ToolKind, cwd: String? = nil, name: String? = nil, accountID: String? = nil, extraArguments: String = "", group: String? = nil, plan: ModelPlan? = nil, then: ((SessionInfo) -> Void)? = nil) {
        guard let command = tool.command else {
            AppModel.shared.newTerminal(cwd: cwd)
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
        env["ENTERM_STARTUP"] = extraArguments.isEmpty ? command : "\(command) \(extraArguments)"
        spec.env = env
        if let reason = PowerCenter.shared.blockReason() {
            PowerCenter.shared.enqueue(spec, reason: reason, then: then)
            AppModel.shared.hint = "Sırada: \(reason). Çalışan İş Durmadı."
            return
        }
        AppModel.shared.create(spec, then: then)
    }
}
