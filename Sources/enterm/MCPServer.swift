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
        tool("ajan_listesi", "Bu oturumun bağlı olduğu ajanları ve durumlarını listeler.", [:], required: []),
        tool("ozet_oku", "Bağlı bir ajanın durumunu ve son ekran satırlarını okur. 'Özetini Görür' bağlantısı gerekir.",
             ["hedef": "Ajanın adı"], required: ["hedef"]),
        tool("is_ver", "Bağlı bir ajana iş ya da mesaj yazar. 'İş Verebilir' bağlantısı gerekir. Mesaj onay sayılmaz.",
             ["hedef": "Ajanın adı", "mesaj": "İş ya da mesaj"], required: ["hedef", "mesaj"]),
        tool("rapor_yaz", "Dört satırlık raporu yazar, varsa pano kartını Kontrolde'ye taşır. Rapor kartı Bitti yapmaz.",
             ["ne_degisti": "Ne değişti", "ne_denendi": "Ne denendi", "ne_denenmedi": "Ne denenmedi", "ne_bekliyor": "Ne bekliyor"],
             required: ["ne_degisti", "ne_denendi", "ne_denenmedi", "ne_bekliyor"]),
        tool("yorum_yaz", "Bu oturumun pano kartına yorum yazar. Ajan yorumu onay sayılmaz.",
             ["metin": "Yorum"], required: ["metin"]),
        tool("tarayici_ac", "Enterm'in dahili tarayıcısında adresi açar. İnternet yetkisine bağlıdır.",
             ["adres": "http ya da https adresi"], required: ["adres"]),
        tool("tarayici_oku", "Açık sayfanın adresini, başlığını ve metnini döndürür.", [:], required: []),
        tool("tarayici_tikla", "Sayfada görünen metni ya da CSS seçicisi verilen öğeye tıklar.",
             ["hedef": "Düğme metni ya da CSS seçici"], required: ["hedef"]),
        tool("tarayici_yaz", "Alana metin yazar. Alan, CSS seçici, ad ya da yer tutucu ile bulunur.",
             ["hedef": "Alan", "metin": "Yazılacak metin"], required: ["hedef", "metin"]),
        tool("tarayici_goruntu", "Sayfanın ekran görüntüsünü PNG dosyasına kaydeder, yolunu döndürür.", [:], required: []),
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
