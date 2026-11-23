import EntermCore
import Foundation

/// The local bridge between agents: JSON-RPC over stdio, started by the official programs.
/// Links and permission cards are checked on every call. A link never grants a permission.
final class MCPServer {
    private let me = ProcessInfo.processInfo.environment["ENTERM_SESSION_ID"] ?? ""

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let id = request["id"]
            let method = request["method"] as? String ?? ""
            let params = request["params"] as? [String: Any] ?? [:]
            guard id != nil else { continue }
            switch method {
            case "initialize":
                reply(id, ["protocolVersion": params["protocolVersion"] ?? "2025-03-26",
                           "capabilities": ["tools": [:]],
                           "serverInfo": ["name": "enterm", "version": EntermVersion.current]])
            case "ping":
                reply(id, [:])
            case "tools/list":
                reply(id, ["tools": Self.tools])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                let (text, failed) = call(name, args)
                reply(id, ["content": [["type": "text", "text": text]], "isError": failed])
            default:
                let error: [String: Any] = ["code": -32601, "message": "Bilinmeyen yöntem"]
                send(["jsonrpc": "2.0", "id": id as Any, "error": error])
            }
        }
    }

    private func reply(_ id: Any?, _ result: [String: Any]) {
        send(["jsonrpc": "2.0", "id": id as Any, "result": result])
    }

    private func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0a)
        FileHandle.standardOutput.write(data)
    }

    private static func tool(_ name: String, _ description: String, _ fields: [String: String], required: [String]) -> [String: Any] {
        var properties: [String: Any] = [:]
        for (key, value) in fields { properties[key] = ["type": "string", "description": value] }
        return ["name": name, "description": description,
                "inputSchema": ["type": "object", "properties": properties, "required": required]]
    }

    static let tools: [[String: Any]] = [
        tool("ajan_listesi", "Lists the agents linked to this session and their status.", [:], required: []),
        tool("ozet_oku", "Reads a linked agent's status and its latest screen lines. Requires a 'Sees Summary' (Özetini Görür) link.",
             ["hedef": "Agent name"], required: ["hedef"]),
        tool("is_ver", "Sends work or a message to a linked agent. Requires a 'Can Assign Work' (İş Verebilir) link. A message does not count as approval.",
             ["hedef": "Agent name", "mesaj": "Work or message"], required: ["hedef", "mesaj"]),
        tool("rapor_yaz", "Writes a four-line report and moves this session's board card, if any, to In Review (Kontrolde). A report never marks a card Done.",
             ["ne_degisti": "What changed", "ne_denendi": "What was tested", "ne_denenmedi": "What was not tested", "ne_bekliyor": "What is pending"],
             required: ["ne_degisti", "ne_denendi", "ne_denenmedi", "ne_bekliyor"]),
        tool("yorum_yaz", "Adds a comment to this session's board card. An agent's comment does not count as approval.",
             ["metin": "Comment"], required: ["metin"]),
        tool("tarayici_ac", "Opens a URL in Enterm's built-in browser. Requires internet permission.",
             ["adres": "http or https URL"], required: ["adres"]),
        tool("tarayici_oku", "Returns the open page's URL, title and text.", [:], required: []),
        tool("tarayici_tikla", "Clicks the element matching the given visible text or CSS selector.",
             ["hedef": "Button text or CSS selector"], required: ["hedef"]),
        tool("tarayici_yaz", "Types text into a field. The field is found by CSS selector, name or placeholder.",
             ["hedef": "Field", "metin": "Text to type"], required: ["hedef", "metin"]),
        tool("tarayici_goruntu", "Saves a screenshot of the page as a PNG file and returns its path.", [:], required: []),
        tool("tuval_durumu", "Lists all boxes on the canvas (name, program, status, project, folder, context), the views and a board summary.", [:], required: []),
        tool("kutu_ac", "Opens a new agent or terminal box on the canvas and gives you a 'Can Assign Work' link to it. Requires the Assigning Work to Other Agents permission on your permission card.",
             ["program": "claude, codex, agy, gemini, opencode, grok, copilot, cursor or terminal (default claude)",
              "ad": "Box name; use it to address the box later", "klasor": "Working folder (default: yours)",
              "gorev": "Work to send to the program as its first message", "sonra": "Open only after the box with this name finishes its work (queues it)"], required: []),
        tool("ekip_kur", "Opens several agents at once, groups them with you and opens a task card for each. At most 6 members.",
             ["ad": "Team name", "uyeler": "Each member as 'name: program: task', members separated by ;",
              "klasor": "Working folder (default: yours)", "kart": "\"hayir\" (no) to skip opening board cards"], required: ["uyeler"]),
        tool("worktree_ac", "Opens a git worktree for a new branch next to the project, starts an agent in it and groups it. Keeps two agents from writing to the same files.",
             ["dal": "New branch name", "program": "Default claude", "ad": "Box name", "gorev": "First message"], required: ["dal"]),
        tool("kutu_kapat", "Closes a box. Only boxes you opened.", ["hedef": "Box name"], required: ["hedef"]),
        tool("kart_ekle", "Adds a card to the board, optionally assigned to a box.",
             ["baslik": "Card title", "aciklama": "Details", "hedef": "Name of the box to assign", "oncelik": "\"yuksek\" (high) or empty"], required: ["baslik"]),
        tool("kart_tasi", "Moves a board card to a column: yapilacak (to do), suruyor (in progress), kontrolde (in review), karar (decision). Only the user moves cards to Done. A card moved to suruyor is sent to its assigned agent.",
             ["kart": "Card title or the first characters of its ID", "sutun": "Target column"], required: ["kart", "sutun"]),
        tool("goster", "Puts something on the canvas: not (note, text), web (URL), gorsel (image) or video (file path).",
             ["tur": "not, web, gorsel (image) or video", "icerik": "Text, URL or file path"], required: ["tur", "icerik"]),
        tool("duzenle", "Arranges the canvas: diz (lines boxes up) or sigdir (fits them all in view).", ["islem": "diz (arrange) or sigdir (fit)"], required: ["islem"]),
    ]

    private func sessions() -> [SessionInfo] {
        WireSocket.send(WireMessage(op: "list"), waitForReply: true, timeout: 2)?.sessions ?? []
    }

    private func call(_ name: String, _ args: [String: Any]) -> (String, Bool) {
        let list = sessions()
        guard let current = list.first(where: { $0.id == me }) else { return ("Bu oturum Enterm'de bulunamadı.", true) }
        let links = LinkBook.load().links
        func displayName(_ info: SessionInfo) -> String { info.name.isEmpty ? "\(info.tool.title) \(info.number)" : info.name }
        func find(_ text: String) -> SessionInfo? {
            list.first { displayName($0).lowercased() == text.lowercased() || $0.id == text }
        }
        switch name {
        case "tarayici_ac", "tarayici_oku", "tarayici_tikla", "tarayici_yaz", "tarayici_goruntu":
            return browser(name, args)
        case "kutu_ac", "ekip_kur", "worktree_ac", "kutu_kapat":
            let what: String
            switch name {
            case "ekip_kur": what = "Ekip Kurmak İstiyor: \(args["uyeler"] as? String ?? "")"
            case "worktree_ac": what = "Worktree Açmak İstiyor: \(args["dal"] as? String ?? "")"
            case "kutu_kapat": what = "Kutu Kapatmak İstiyor: \(args["hedef"] as? String ?? "")"
            default: what = "Kutu Açmak İstiyor: \(args["program"] as? String ?? "claude") · \(args["gorev"] as? String ?? args["ad"] as? String ?? "")"
            }
            guard allowed(.delegate, what) else { return ("İzin verilmedi. Yetki kartınızda Başka Ajana İş Verme kapalı ya da kullanıcı reddetti.", true) }
            return canvas(name, args)
        case "tuval_durumu", "kart_ekle", "kart_tasi", "goster", "duzenle":
            return canvas(name, args)
        case "ajan_listesi":
            let visible = list.filter { other in
                other.id != me && links.contains { $0.allows(from: me, to: other.id, need: .summary) }
            }
            if visible.isEmpty { return ("Bağlı ajan yok. Kullanıcı tuvalde bağlantı çizmeli.", false) }
            return (visible.map { "\(displayName($0)): \($0.status.title)" }.joined(separator: "\n"), false)
        case "ozet_oku":
            guard let target = find(args["hedef"] as? String ?? "") else { return ("Bu adla ajan yok.", true) }
            guard links.contains(where: { $0.allows(from: me, to: target.id, need: .summary) }) else {
                return ("Bu ajana bağlantınız yok. Bağlantıyı yalnız kullanıcı kurar.", true)
            }
            var message = WireMessage(op: "tail")
            message.number = target.number
            let tail = WireSocket.send(message, waitForReply: true, timeout: 2)?.text ?? ""
            return ("Durum: \(target.status.title)\nSon Etkinlik: \(target.lastActivity ?? "Yok")\n\n\(tail)", false)
        case "is_ver":
            guard let target = find(args["hedef"] as? String ?? "") else { return ("Bu adla ajan yok.", true) }
            guard links.contains(where: { $0.allows(from: me, to: target.id, need: .delegate) }) else {
                return ("'İş Verebilir' bağlantınız yok.", true)
            }
            let book = PermissionBook.load()
            guard book.card(for: me).mode(.delegate) != .deny else {
                return ("Yetki kartınızda başka ajana iş verme kapalı. Yetkisi olmayan iş devredilemez.", true)
            }
            let text = (args["mesaj"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
            let mail = AgentMail(from: me, fromName: displayName(current), to: target.id, toName: displayName(target), kind: "İş", text: text)
            MailBox.append(mail)
            var input = WireMessage(op: "input")
            input.number = target.number
            input.text = "[Ajan Mesajı, \(displayName(current))] \(text)\r"
            _ = WireSocket.send(input)
            var reload = WireMessage(op: "reload")
            reload.text = mail.claimedApproval ? "Onay Sayılmadı: \(displayName(current)) Bir Onay İddia Etti" : nil
            _ = WireSocket.send(reload)
            let warning = mail.claimedApproval ? " Uyarı: Ajan mesajı onay sayılmaz, hedefin izinleri değişmedi." : ""
            return ("Mesaj iletildi.\(warning)", false)
        case "rapor_yaz":
            let report = AgentReport(author: displayName(current), changed: args["ne_degisti"] as? String ?? "",
                                     tried: args["ne_denendi"] as? String ?? "", notTried: args["ne_denenmedi"] as? String ?? "",
                                     waiting: args["ne_bekliyor"] as? String ?? "")
            return writeReport(report, session: current)
        case "yorum_yaz":
            var board = Board.load()
            guard let index = board.cards.firstIndex(where: { $0.sessionID == me }) else { return ("Bu oturumun pano kartı yok.", true) }
            board.cards[index].comments.append(CardComment(author: displayName(current), isAgent: true, text: args["metin"] as? String ?? ""))
            board.save()
            _ = WireSocket.send(WireMessage(op: "reload"))
            return ("Yorum eklendi.", false)
        default:
            return ("Bilinmeyen araç.", true)
        }
    }

    /// The permission card decides: allowed goes on, ask shows the person the request, denied stops here.
    private func allowed(_ category: PermissionCategory, _ text: String) -> Bool {
        var event = AgentEvent(sessionID: me, kind: "approval")
        event.tool = "Tuval"
        event.text = text
        event.errorKind = category.rawValue
        var request = WireMessage(op: "approval")
        request.event = event
        return WireSocket.send(request, waitForReply: true, timeout: 590)?.decision == "allow"
    }

    private func canvas(_ name: String, _ args: [String: Any]) -> (String, Bool) {
        var message = WireMessage(op: "canvas")
        let payload: [String: Any] = ["name": name, "args": args]
        message.text = (try? JSONSerialization.data(withJSONObject: payload)).map { String(decoding: $0, as: UTF8.self) }
        message.event = AgentEvent(sessionID: me, kind: "canvas")
        guard let reply = WireSocket.send(message, waitForReply: true, timeout: 30) else { return ("Enterm yanıt vermedi.", true) }
        if let error = reply.error { return (error, true) }
        return (reply.text ?? "", false)
    }

    private func browser(_ name: String, _ args: [String: Any]) -> (String, Bool) {
        if name == "tarayici_ac" {
            let address = args["adres"] as? String ?? ""
            let host = PermissionClassifier.hostOf(address) ?? ""
            let local = ["localhost", "127.0.0.1", "::1"].contains(host) || host.hasSuffix(".localhost") || host.hasSuffix(".test")
            if !local {
                var event = AgentEvent(sessionID: me, kind: "approval")
                event.tool = "Tarayıcı"
                event.text = address
                event.errorKind = PermissionCategory.internet.rawValue
                event.model = host
                var request = WireMessage(op: "approval")
                request.event = event
                guard WireSocket.send(request, waitForReply: true, timeout: 590)?.decision == "allow" else {
                    return ("İnternet yetkisi verilmedi: \(host)", true)
                }
            }
        }
        var message = WireMessage(op: "browser")
        let payload: [String: Any] = ["name": name, "args": args]
        message.text = (try? JSONSerialization.data(withJSONObject: payload)).map { String(decoding: $0, as: UTF8.self) }
        message.event = AgentEvent(sessionID: me, kind: "browser")
        guard let reply = WireSocket.send(message, waitForReply: true, timeout: 40) else { return ("Tarayıcı yanıt vermedi.", true) }
        if let error = reply.error { return (error, true) }
        return (reply.text ?? "", false)
    }

    private func writeReport(_ report: AgentReport, session: SessionInfo) -> (String, Bool) {
        var report = report
        var team = Team.load()
        let folder = (team?.folder.isEmpty == false ? team?.folder : nil) ?? session.cwd
        let dir = URL(fileURLWithPath: folder).appendingPathComponent("ekip/raporlar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let slug = report.author.lowercased().replacingOccurrences(of: " ", with: "-")
        let file = dir.appendingPathComponent("\(formatter.string(from: report.at))-\(slug).md")
        let body = "# \(report.author) Raporu\n\n**Ne Değişti:** \(report.changed)\n\n**Ne Denendi:** \(report.tried)\n\n**Ne Denenmedi:** \(report.notTried)\n\n**Ne Bekliyor:** \(report.waiting)\n"
        try? body.write(to: file, atomically: true, encoding: .utf8)
        report.file = file.path
        team?.reports.insert(report, at: 0)
        team?.save()
        var board = Board.load()
        board.applyReport(sessionID: me, report: report)
        board.save()
        var reload = WireMessage(op: "reload")
        reload.text = "Rapor Geldi: \(report.author)"
        _ = WireSocket.send(reload)
        return ("Rapor yazıldı: \(file.path)", false)
    }
}
