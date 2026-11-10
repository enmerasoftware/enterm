import AppKit
import EntermCore
import Foundation

/// What an agent may do on the canvas through the bridge: see it, open and close its own boxes, build a team,
/// open a worktree, work the board and put things on the surface. The bridge has already asked the person
/// where the permission card says so; this side only carries it out and says what happened.
enum CanvasAgent {
    /// Boxes waiting for another session to finish its turn: the session's id, then what to start.
    private static var waiting: [String: [() -> Void]] = [:]

    static func handle(_ message: WireMessage) {
        guard let id = message.id else { return }
        func reply(_ text: String?, _ error: String? = nil) {
            var answer = WireMessage(op: "canvasReply")
            answer.id = id
            answer.text = text
            answer.error = error
            AppModel.shared.connection.send(answer)
        }
        guard let data = message.text?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String else { return reply(nil, "İstek okunamadı.") }
        let args = (object["args"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String ?? ($0 as? NSNumber)?.stringValue }
        let model = AppModel.shared
        guard let caller = model.sessions.first(where: { $0.id == message.event?.sessionID }) else { return reply(nil, "Bu oturum Enterm'de bulunamadı.") }
        switch run(name, args, caller: caller) {
        case .success(let text): reply(text)
        case .failure(let error): reply(nil, error.text)
        }
    }

    struct Failure: Error { let text: String }

    private static func run(_ name: String, _ args: [String: String], caller: SessionInfo) -> Result<String, Failure> {
        let model = AppModel.shared
        switch name {
        case "tuval_durumu": return .success(overview(caller: caller))
        case "kutu_ac": return open(args, caller: caller, group: nil, card: nil)
        case "ekip_kur": return team(args, caller: caller)
        case "worktree_ac":
            let branch = (args["dal"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !branch.isEmpty, branch.range(of: #"^[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil else {
                return .failure(Failure(text: "Dal adı boş ya da geçersiz: harf, rakam, nokta, tire, alt çizgi ve / kullanın."))
            }
            let tool = args["program"].flatMap(Self.tool) ?? .claude
            let label = uniqueName(args["ad"] ?? branch)
            if let error = WorktreeActions.create(branch: branch, tool: tool, name: label, extraArguments: task(args["gorev"]),
                                                  then: { info in adopt(info, by: caller) }) {
                return .failure(Failure(text: error))
            }
            note("\(display(caller)) Worktree Açtı: \(branch)")
            return .success("Worktree açılıyor: \(branch), oturum adı \(label). Bağlantınız İş Verebilir olarak kuruldu.")
        case "kutu_kapat":
            guard let target = find(args["hedef"]) else { return .failure(Failure(text: "Bu adla kutu yok.")) }
            guard model.state.openedBy[target.id] == caller.id else {
                return .failure(Failure(text: "Yalnız kendi açtığınız kutuyu kapatabilirsiniz. Diğerlerini kullanıcı kapatır."))
            }
            model.close(target.number)
            model.state.openedBy[target.id] = nil
            note("\(display(caller)) \(display(target)) Kutusunu Kapattı")
            return .success("Kapatıldı: \(display(target))")
        case "kart_ekle":
            let title = (args["baslik"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return .failure(Failure(text: "Kart başlığı boş.")) }
            var card = BoardCard(title: title)
            card.details = args["aciklama"] ?? ""
            card.priority = args["oncelik"] == "yuksek" ? 1 : 0
            if let target = find(args["hedef"]) {
                card.sessionID = target.id
                card.members = [display(target)]
            }
            BoardStore.shared.change { $0.cards.append(card) }
            note("\(display(caller)) Panoya Kart Ekledi")
            return .success("Kart eklendi: \(title) (kimlik \(card.id.prefix(8)))")
        case "kart_tasi":
            guard let column = Self.column(args["sutun"]) else {
                return .failure(Failure(text: "Sütun: yapilacak, suruyor, kontrolde ya da karar. Bitti'ye yalnız kullanıcı alır."))
            }
            let key = (args["kart"] ?? "").lowercased()
            guard let card = BoardStore.shared.board.cards.first(where: { $0.id.lowercased().hasPrefix(key) && key.count >= 4 || $0.title.lowercased() == key }) else {
                return .failure(Failure(text: "Kart bulunamadı. Başlığını ya da kimliğinin ilk harflerini verin."))
            }
            BoardStore.shared.change { board in
                if let index = board.cards.firstIndex(where: { $0.id == card.id }) { board.cards[index].column = column }
            }
            BoardDispatch.cardMoved(id: card.id, to: column)
            IssueSync.cardMoved(id: card.id, to: column)
            return .success("\(card.title) → \(column.title)")
        case "goster":
            return show(args, caller: caller)
        case "duzenle":
            switch args["islem"] {
            case "diz": Commands.perform("arrange")
            case "sigdir": Commands.perform("fit")
            default: return .failure(Failure(text: "islem: diz ya da sigdir."))
            }
            return .success("Tamam.")
        default:
            return .failure(Failure(text: "Bilinmeyen araç."))
        }
    }

    // MARK: Boxes

    private static func open(_ args: [String: String], caller: SessionInfo, group: String?, card: String?) -> Result<String, Failure> {
        let model = AppModel.shared
        let tool = args["program"].flatMap(Self.tool) ?? .claude
        let folder = expand(args["klasor"]) ?? caller.cwd
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder), isFolder.boolValue else {
            return .failure(Failure(text: "Klasör yok: \(folder)"))
        }
        let label = uniqueName(args["ad"] ?? tool.title)
        let start = {
            let adopt: (SessionInfo) -> Void = { info in
                Self.adopt(info, by: caller, card: card)
                if let group { model.addToGroup(info.id, group: group) }
            }
            if tool == .terminal {
                model.create(SessionSpec(name: label, tool: .terminal, cwd: folder, rows: 30, cols: 100), then: adopt)
            } else {
                ToolLauncher.start(tool, cwd: folder, name: label, extraArguments: task(args["gorev"]), announcesQueue: false, then: adopt)
            }
        }
        if let after = args["sonra"], !after.isEmpty {
            guard let previous = find(after) else { return .failure(Failure(text: "Beklenecek kutu yok: \(after)")) }
            waiting[previous.id, default: []].append(start)
            note("\(display(caller)) Bir Kutuyu Sıraya Koydu: \(label), \(display(previous)) Bitince")
            return .success("\(label), \(display(previous)) işini bitirince açılacak.")
        }
        start()
        note("\(display(caller)) Kutu Açtı: \(label)")
        return .success("Açılıyor: \(label) (\(tool.title), \(model.displayPath(folder))). Bağlantınız İş Verebilir olarak kuruldu; is_ver ve ozet_oku ile yönetin.")
    }

    /// `uyeler`: one member per line or separated by ";", as `ad: program: görev`.
    private static func team(_ args: [String: String], caller: SessionInfo) -> Result<String, Failure> {
        let model = AppModel.shared
        let members = (args["uyeler"] ?? "").components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !members.isEmpty else { return .failure(Failure(text: "uyeler boş. Örnek: Arayüz: claude: giriş sayfasını yap; Test: codex: testleri yaz")) }
        guard members.count <= 6 else { return .failure(Failure(text: "Bir seferde en çok 6 üye. Gerekirse sonra ekleyin.")) }
        let name = (args["ad"] ?? "Ekip").trimmingCharacters(in: .whitespaces)
        model.addToNewGroup(caller.id, name: name)
        guard let group = model.state.groups.last?.id else { return .failure(Failure(text: "Grup kurulamadı.")) }
        var opened: [String] = []
        for line in members {
            let parts = line.split(separator: ":", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
            var fields = ["ad": parts[0], "program": parts.count > 1 ? parts[1] : "claude", "klasor": args["klasor"] ?? ""]
            if parts.count > 2 { fields["gorev"] = parts[2] }
            var cardID: String?
            if args["kart"] != "hayir", parts.count > 2 {
                var card = BoardCard(title: parts[2])
                card.members = [parts[0]]
                card.column = .doing
                BoardStore.shared.change { $0.cards.append(card) }
                cardID = card.id
            }
            switch open(fields.filter { !$0.value.isEmpty }, caller: caller, group: group, card: cardID) {
            case .success: opened.append(parts[0])
            case .failure(let error): return .failure(Failure(text: "\(parts[0]) açılamadı: \(error.text). Açılanlar: \(opened.joined(separator: ", "))"))
            }
        }
        return .success("Ekip \(name): \(opened.joined(separator: ", ")). Hepsi sizinle aynı grupta, İş Verebilir bağlantılı. Bitince rapor_yaz ile raporlarlar.")
    }

    /// The agent that opened a box can give it work and read it; the box shows up linked on the canvas.
    private static func adopt(_ info: SessionInfo, by caller: SessionInfo, card cardID: String? = nil) {
        let model = AppModel.shared
        model.state.openedBy[info.id] = caller.id
        model.saveState()
        LinkStore.shared.add(SessionLink(from: caller.id, to: info.id, permission: .delegate, bothWays: false))
        if let cardID {
            BoardStore.shared.change { board in
                if let index = board.cards.firstIndex(where: { $0.id == cardID }) { board.cards[index].sessionID = info.id }
            }
        }
    }

    /// A queued box opens when the session it waits for finishes its turn, or ends.
    static func sessionUpdated(previous: SessionInfo, current: SessionInfo) {
        guard let queue = waiting[current.id], previous.status == .running || previous.status == .needsApproval,
              [.idle, .exited, .failed].contains(current.status) else { return }
        waiting[current.id] = nil
        queue.forEach { $0() }
    }

    // MARK: Surface

    private static func show(_ args: [String: String], caller: SessionInfo) -> Result<String, Failure> {
        let model = AppModel.shared
        let content = (args["icerik"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return .failure(Failure(text: "icerik boş.")) }
        switch args["tur"] ?? "not" {
        case "not":
            model.addItem(.note, text: content)
        case "web":
            guard let url = URL(string: content), ["http", "https"].contains(url.scheme ?? "") else {
                return .failure(Failure(text: "web için http ya da https adresi verin."))
            }
            model.addItem(.web, text: content)
        case "gorsel", "video":
            guard let path = expand(content), FileManager.default.fileExists(atPath: path) else { return .failure(Failure(text: "Dosya yok: \(content)")) }
            if args["tur"] == "video" {
                model.addItem(.video, text: path)
            } else {
                model.addItem(.web, text: URL(fileURLWithPath: path).absoluteString)
            }
        default:
            return .failure(Failure(text: "tur: not, web, gorsel ya da video."))
        }
        note("\(display(caller)) Tuvale Ekledi")
        return .success("Tuvale eklendi.")
    }

    private static func overview(caller: SessionInfo) -> String {
        let model = AppModel.shared
        var lines = model.sessions.map { info -> String in
            var line = "- \(display(info)) · \(info.tool.title) · \(info.status.title) · \(model.project(of: info)) · \(model.displayPath(info.cwd))"
            if info.id == caller.id { line += " · siz" }
            if model.state.openedBy[info.id] == caller.id { line += " · sizin açtığınız" }
            if let percent = info.contextPercent { line += " · bağlam %\(percent)" }
            if let title = info.title { line += " · başlık: \(title)" }
            if let loop = info.loop { line += " · döngü: \(loop)" }
            if let ports = info.ports { line += " · port " + ports.map(String.init).joined(separator: ", ") }
            return line
        }
        let items = model.state.items.map { "- \($0.title)" }
        if !items.isEmpty { lines.append("Görünümler:"); lines += items }
        let board = BoardStore.shared.board.cards
        if !board.isEmpty {
            lines.append("Pano: " + BoardColumn.allCases.map { column in "\(column.title) \(board.filter { $0.column == column }.count)" }.joined(separator: ", "))
        }
        let queued = waiting.values.reduce(0) { $0 + $1.count }
        if queued > 0 { lines.append("Sırada bekleyen kutu: \(queued)") }
        return lines.joined(separator: "\n")
    }

    // MARK: Helpers

    private static func display(_ info: SessionInfo) -> String { info.name.isEmpty ? "\(info.tool.title) \(info.number)" : info.name }

    private static func find(_ text: String?) -> SessionInfo? {
        guard let text = text?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return nil }
        return AppModel.shared.sessions.first { display($0).lowercased() == text || $0.id == text }
    }

    private static func uniqueName(_ wanted: String) -> String {
        let base = wanted.trimmingCharacters(in: .whitespaces).isEmpty ? "Ajan" : wanted.trimmingCharacters(in: .whitespaces)
        let taken = Set(AppModel.shared.sessions.map { display($0).lowercased() })
        var name = base, index = 2
        while taken.contains(name.lowercased()) { name = "\(base) \(index)"; index += 1 }
        return name
    }

    /// The first message goes in as the program's own start argument, so it is typed by nobody.
    private static func task(_ text: String?) -> String {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "" }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func expand(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespaces), !path.isEmpty else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    static func tool(_ name: String) -> ToolKind? {
        switch name.lowercased().trimmingCharacters(in: .whitespaces) {
        case "claude", "claude code": return .claude
        case "codex": return .codex
        case "agy", "antigravity": return .antigravity
        case "gemini": return .gemini
        case "opencode": return .opencode
        case "grok": return .grok
        case "copilot", "github copilot": return .copilot
        case "cursor", "cursor-agent": return .cursor
        case "terminal", "kabuk": return .terminal
        default: return nil
        }
    }

    static func column(_ name: String?) -> BoardColumn? {
        switch name?.lowercased() {
        case "yapilacak", "yapılacak", "todo": return .todo
        case "suruyor", "sürüyor", "doing": return .doing
        case "kontrolde", "review": return .review
        case "karar", "karar bekliyor", "decision": return .decision
        default: return nil
        }
    }

    /// The person always sees what an agent did on the canvas.
    private static func note(_ text: String) { AppModel.shared.hint = text }
}

/// What an `enterm://` address does. Starting a program always asks first: the address may come from a web page.
enum URLActions {
    static func perform(_ link: EntermURL) {
        let model = AppModel.shared
        NSApp.activate(ignoringOtherApps: true)
        switch link {
        case .open(let path, let program, let name, let task):
            let folder = (path as NSString).expandingTildeInPath
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder), isFolder.boolValue else {
                model.hint = "Klasör Yok: \(path)"
                return
            }
            let tool = program.flatMap(CanvasAgent.tool) ?? .terminal
            var detail = "\(tool.title) şu klasörde açılacak: \(model.displayPath(folder))."
            if let task { detail += "\n\nİlk mesaj: \(task.prefix(400))" }
            model.confirm(title: "Bir Bağlantı Oturum Açmak İstiyor", detail: detail, action: "Aç") {
                if tool == .terminal {
                    model.create(SessionSpec(name: name, tool: .terminal, cwd: folder, rows: 30, cols: 100))
                } else {
                    let first = task.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" } ?? ""
                    ToolLauncher.start(tool, cwd: folder, name: name, extraArguments: first)
                }
            }
        case .session(let name):
            let wanted = name.lowercased()
            if let info = model.sessions.first(where: { model.name(for: $0).lowercased() == wanted || $0.name.lowercased() == wanted }) {
                let project = model.project(of: info)
                if !model.showsAllProjects, model.activeProject != project { model.switchProject(project) }
                model.setFocus(info.number)
            } else {
                model.hint = "Oturum Yok: \(name)"
            }
        case .settings(let tab):
            model.page = .settings(SettingsTab(rawValue: tab) ?? .programs)
        case .page(let name):
            switch name {
            case "board": Commands.perform("board")
            case "commands": model.page = .settings(.commands)
            default: model.page = .settings(.skills)
            }
        }
    }
}
