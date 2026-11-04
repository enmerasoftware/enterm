import AppKit
import EntermCore
import WebKit

/// Answers what the phone asks, with the same stores and actions the Mac's screens use.
enum PhoneBridge {
    static func handle(_ message: WireMessage) {
        guard let id = message.id else { return }
        func answer(_ text: String?, _ error: String? = nil) {
            var reply = WireMessage(op: "appReply")
            reply.id = id
            reply.text = text
            reply.error = error
            AppModel.shared.connection.send(reply)
        }
        func send<T: Encodable>(_ value: T) {
            answer((try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) })
        }
        guard let data = message.text?.data(using: .utf8), let call = try? JSONDecoder().decode(PhoneCall.self, from: data) else {
            answer(nil, "Geçersiz İstek")
            return
        }
        let model = AppModel.shared
        let info = call.number.flatMap { number in model.sessions.first { $0.number == number } }
        let args = call.args
        switch call.name {
        case "options":
            ToolCatalog.shared.refresh()
            var notes: [String: String] = [:]
            for tool in ToolKind.allCases { notes[tool.rawValue] = ToolCatalog.shared.note(tool) }
            let folders = Array(Set(model.sessions.map { model.displayPath($0.cwd) })).sorted()
            send(PhoneOptions(accounts: accounts(), folders: folders, notes: notes, plan: SettingsStore.shared.settings.defaultPlan))
        case "start":
            start(args, send: send, fail: { answer(nil, $0) })
        case "install":
            guard let tool = args["tool"].flatMap(ToolKind.init(rawValue:)) else { return answer(nil, "Geçersiz Program") }
            InstallToolActions.run(tool)
            send(PhoneNothing())
        case "foundCard":
            guard let number = call.number, let command = args["command"], let card = NotFoundCard.make(number: number, command: command) else {
                return answer(nil, "Kart Yok")
            }
            send(foundCard(card))
        case "accounts":
            AccountStore.shared.refreshCodex()
            send(accounts())
        case "accountAdd":
            AccountStore.shared.beginLogin(tool: args["tool"] == "codex" ? .codex : .claude, name: args["name"] ?? "")
            send(PhoneNothing())
        case "limitChoices":
            guard let info else { return answer(nil, "Oturum Bulunamadı") }
            let actions = LimitActions.options(for: info)
            LimitActions.current = actions.map(\.run)
            send(actions.enumerated().map { PhoneChoice(id: $0.offset, title: $0.element.title, note: $0.element.note) })
        case "limitRun":
            LimitActions.perform(index: Int(args["index"] ?? "") ?? -1)
            send(PhoneNothing())
        case "changes":
            guard let info else { return answer(nil, "Oturum Bulunamadı") }
            let runner = CommandRunner(remote: model.remotes[info.number], folder: info.cwd)
            DispatchQueue.global(qos: .userInitiated).async {
                let result = changes(runner)
                DispatchQueue.main.async { send(result) }
            }
        case "diff":
            guard let info, let path = args["path"] else { return answer(nil, "Oturum Bulunamadı") }
            let runner = CommandRunner(remote: model.remotes[info.number], folder: info.cwd)
            DispatchQueue.global(qos: .userInitiated).async {
                let tracked = Git.run(["diff", "HEAD", "--", path], runner: runner).output
                let text = tracked.isEmpty ? Git.run(["diff", "--no-index", "--", "/dev/null", path], runner: runner).output : tracked
                // A very large change stays readable on a phone, and on the relay.
                let shown = String(text.prefix(200_000))
                DispatchQueue.main.async { answer(shown) }
            }
        case "browser":
            BrowserCenter.shared.phoneState { send($0) }
        case "browserOpen":
            guard let address = args["address"] else { return answer(nil, "Adres Yok") }
            BrowserCenter.shared.load(address)
            send(PhoneNothing())
        case "browserControl":
            BrowserCenter.shared.userHasControl = args["on"] == "1"
            send(PhoneNothing())
        case "browserTap":
            BrowserCenter.shared.phoneTap(x: Double(args["x"] ?? "") ?? 0, y: Double(args["y"] ?? "") ?? 0)
            send(PhoneNothing())
        case "browserScroll":
            BrowserCenter.shared.phoneScroll(by: Double(args["by"] ?? "") ?? 0)
            send(PhoneNothing())
        case "browserType":
            BrowserCenter.shared.phoneType(args["text"] ?? "")
            send(PhoneNothing())
        case "links":
            send(LinkStore.shared.links.map { link in
                PhoneLink(id: link.id, fromName: name(link.from), toName: name(link.to), permission: link.permission, bothWays: link.bothWays)
            })
        case "linkAdd":
            guard let source = info, let target = args["to"].flatMap(UInt32.init).flatMap({ number in model.sessions.first { $0.number == number } }),
                  let permission = args["permission"].flatMap(LinkPermission.init(rawValue:)) else { return answer(nil, "Oturum Bulunamadı") }
            LinkStore.shared.add(SessionLink(from: source.id, to: target.id, permission: permission, bothWays: args["both"] == "1"))
            send(PhoneNothing())
        case "linkRemove":
            LinkStore.shared.remove(args["id"] ?? "")
            send(PhoneNothing())
        case "messages":
            guard let info else { return answer(nil, "Oturum Bulunamadı") }
            send(MailBox.all().filter { $0.from == info.id || $0.to == info.id }.suffix(100))
        case "card":
            guard let info else { return answer(nil, "Oturum Bulunamadı") }
            send(PermissionBook.load().card(for: info.id))
        case "cardSet":
            guard let info, let category = args["category"].flatMap(PermissionCategory.init(rawValue:)),
                  let mode = args["mode"].flatMap(PermissionMode.init(rawValue:)) else { return answer(nil, "Geçersiz Seçim") }
            var book = PermissionBook.load()
            var card = book.card(for: info.id)
            card.modes[category] = mode
            book.cards[info.id] = card
            book.save()
            model.connection.send(WireMessage(op: "reloadPermissions"))
            send(card)
        case "team":
            send(TeamStore.shared.team ?? Team())
        case "teamBuild":
            guard let brief = args["brief"], let folder = args["folder"],
                  let data = args["members"]?.data(using: .utf8), let members = try? JSONDecoder().decode([TeamMember].self, from: data) else {
                return answer(nil, "Kadro Okunamadı")
            }
            let path = (folder as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return answer(nil, "Klasör Bulunamadı")
            }
            TeamBuilder.build(brief: brief, folder: path, members: members)
            send(PhoneNothing())
        case "power":
            send(power())
        case "powerSet":
            let center = PowerCenter.shared
            if let value = args["lowPower"] { center.settings.lowPower = value == "1" }
            if let value = args["cpuLimit"].flatMap(Int.init) { center.settings.cpuLimit = value }
            if let value = args["automatic"] { center.settings.sessionsAutomatic = value == "1" }
            if let value = args["maxSessions"].flatMap(Int.init) { center.settings.maxSessions = max(1, value) }
            send(power())
        default:
            answer(nil, "Bilinmeyen İstek")
        }
    }

    private static func name(_ sessionID: String) -> String {
        AppModel.shared.sessions.first { $0.id == sessionID }.map { AppModel.shared.name(for: $0) } ?? "Kapalı"
    }

    private static func accounts() -> [PhoneAccount] {
        let model = AppModel.shared
        return AccountStore.shared.accounts.map { account in
            let count = model.sessions.filter { ($0.accountID ?? "system-\($0.tool.rawValue)") == account.id }.count
            return PhoneAccount(id: account.id, tool: account.tool, name: account.name, isAPIKey: account.kind == .apiKey, sessions: count, limit: account.lastLimit)
        }
    }

    private static func power() -> PhonePower {
        let center = PowerCenter.shared
        center.measureUsage()
        return PhonePower(settings: center.settings, effectiveSessions: center.effectiveMaxSessions,
                          enterm: String(format: "%%%.1f · %.0f MB", center.enterm.cpu, center.enterm.memoryMB),
                          agents: String(format: "%%%.1f · %.0f MB", center.agents.cpu, center.agents.memoryMB))
    }

    private static func foundCard(_ card: NotFoundCard) -> PhoneFoundCard {
        let run = NotFoundActions.command(for: card)
        switch card.kind {
        case .notInstalled:
            return PhoneFoundCard(title: card.title, command: run, note: "Komut bilgisayarda, bu terminalde görünür şekilde çalışır.", button: "Bu Terminalde Çalıştır")
        case .notInPath, .inApp:
            return PhoneFoundCard(title: card.title, command: run, note: "Enterm bu kopyayı tam yolla çalıştırır, PATH değişmez.", button: "Buradan Çalıştır")
        case .geminiRejected:
            return PhoneFoundCard(title: card.title, command: run, note: "Kişisel hesaplar için resmi program Antigravity (agy).", button: "agy Çalıştır")
        }
    }

    /// The Mac's own starting path: the shell's PATH, a copy outside it, the account, the plan and the queue.
    private static func start(_ args: [String: String], send: @escaping (PhoneStart) -> Void, fail: @escaping (String) -> Void) {
        let model = AppModel.shared
        let tool = args["tool"].flatMap(ToolKind.init(rawValue:)) ?? .terminal
        let name = args["name"].flatMap { $0.isEmpty ? nil : $0 }
        var folder: String?
        if let text = args["folder"], !text.isEmpty {
            let path = (text as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return fail("Klasör Bulunamadı")
            }
            folder = path
        }
        if tool == .terminal {
            model.create(SessionSpec(name: name, tool: .terminal, cwd: folder ?? NSHomeDirectory(), rows: 30, cols: 100)) { send(PhoneStart(number: $0.number)) }
            return
        }
        if ToolCatalog.shared.isMissing(tool) {
            send(PhoneStart(missingTool: tool))
            return
        }
        var plan = SettingsStore.shared.settings.defaultPlan
        if let value = args["model"], !value.isEmpty { plan.main = value }
        if let value = args["effort"], !value.isEmpty { plan.mainEffort = value }
        let account = args["account"].flatMap { $0.isEmpty || $0.hasPrefix("system-") ? nil : $0 }
        let template = args["template"].flatMap(PermissionTemplate.init(rawValue:))
        let before = PowerCenter.shared.queue.count
        ToolLauncher.start(tool, cwd: folder ?? NSHomeDirectory(), name: name, accountID: account, plan: plan) { info in
            if let template {
                var book = PermissionBook.load()
                book.cards[info.id] = template.card
                book.save()
                model.connection.send(WireMessage(op: "reloadPermissions"))
            }
            send(PhoneStart(number: info.number))
        }
        if PowerCenter.shared.queue.count > before { send(PhoneStart(queued: true)) }
        // The launcher may have put up the install card on the Mac after a fresh look at the shell.
        if case .installTool(let missing)? = model.overlay {
            model.overlay = nil
            send(PhoneStart(missingTool: missing))
        }
    }

    private static func changes(_ runner: CommandRunner) -> PhoneChanges {
        guard Git.run(["rev-parse", "--show-toplevel"], runner: runner).ok else {
            return PhoneChanges(isRepository: false, branch: "", files: [])
        }
        let branch = Git.run(["branch", "--show-current"], runner: runner).output.trimmingCharacters(in: .whitespacesAndNewlines)
        var files: [String: PhoneChangedFile] = [:]
        for line in Git.run(["diff", "HEAD", "--numstat"], runner: runner).output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { continue }
            files[parts[2]] = PhoneChangedFile(path: parts[2], added: Int(parts[0]) ?? 0, removed: Int(parts[1]) ?? 0, isNew: false)
        }
        for path in Git.run(["ls-files", "--others", "--exclude-standard"], runner: runner).output.split(separator: "\n").map(String.init) {
            let lines = Git.run(["diff", "--no-index", "--numstat", "--", "/dev/null", path], runner: runner).output
            let added = lines.split(separator: "\t").first.flatMap { Int($0) } ?? 0
            files[path] = PhoneChangedFile(path: path, added: added, removed: 0, isNew: true)
        }
        return PhoneChanges(isRepository: true, branch: branch, files: files.values.sorted { $0.path < $1.path })
    }
}

extension BrowserCenter {
    /// The picture is small and comes only when asked. It costs nothing while nobody looks.
    func phoneState(_ done: @escaping (PhoneBrowser) -> Void) {
        let state = { [self] (image: Data?) in
            PhoneBrowser(isOpen: isOpen, address: address, agent: agentName, lastStep: steps.first, userHasControl: userHasControl, failure: failure, image: image)
        }
        guard isOpen, let view = webView else {
            done(state(nil))
            return
        }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 480
        view.takeSnapshot(with: configuration) { image, _ in
            var jpeg: Data?
            if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.55])
            }
            done(state(jpeg))
        }
    }

    func phoneTap(x: Double, y: Double) {
        guard let view = webView else { return }
        let script = """
        (function(){var w=innerWidth*\(x),h=innerHeight*\(y);var e=document.elementFromPoint(w,h);if(!e)return;e.focus&&e.focus();e.click&&e.click();})()
        """
        view.evaluateJavaScript(script, completionHandler: nil)
    }

    func phoneScroll(by amount: Double) {
        webView?.evaluateJavaScript("window.scrollBy(0, innerHeight*\(amount))", completionHandler: nil)
    }

    func phoneType(_ text: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]) else { return }
        let literal = String(decoding: data, as: UTF8.self).dropFirst().dropLast()
        let script = """
        (function(){var e=document.activeElement;if(!e||!('value' in e))return;var p=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;var d=Object.getOwnPropertyDescriptor(p,'value');if(d&&d.set)d.set.call(e,\(literal));else e.value=\(literal);e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));})()
        """
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
}
