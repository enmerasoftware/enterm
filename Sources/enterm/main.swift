import Darwin
import EntermCore
import Foundation

// The small companion command. Sessions call it from the shell integration and from hooks.
// It must stay silent and quick: a hook's stdout can be read as a decision by the program.

let arguments = Array(CommandLine.arguments.dropFirst())
let environment = ProcessInfo.processInfo.environment
let sessionID = environment["ENTERM_SESSION_ID"] ?? ""
let selfPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path

func sendEvent(_ event: AgentEvent) {
    var message = WireMessage(op: "event")
    message.event = event
    _ = WireSocket.send(message)
}

func readInput() -> [String: Any] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

func output(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    FileHandle.standardOutput.write(data)
}

func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

func findInPath(_ name: String) -> String? {
    for dir in (environment["PATH"] ?? "").split(separator: ":") {
        let candidate = "\(dir)/\(name)"
        if access(candidate, X_OK) == 0 { return candidate }
    }
    return nil
}

func execute(_ path: String, _ argv: [String], extraEnv: [String: String] = [:], removeEnv: [String] = []) -> Never {
    for (key, value) in extraEnv { setenv(key, value, 1) }
    for key in removeEnv { unsetenv(key) }
    let cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
    execv(path, cArgs)
    perror(path)
    exit(127)
}

// MARK: Starting the official programs, unchanged, with documented start arguments

func hookCommand(_ tool: String) -> String { "\(quote(selfPath)) hook \(tool)" }

func writeClaudeFiles() -> (settings: String, mcp: String) {
    func hook(_ timeout: Int? = nil) -> [String: Any] {
        var entry: [String: Any] = ["type": "command", "command": hookCommand("claude")]
        if let timeout { entry["timeout"] = timeout }
        return ["hooks": [entry]]
    }
    let quick = [hook()]
    let settings: [String: Any] = [
        "statusLine": ["type": "command", "command": "\(quote(selfPath)) statusline"],
        "hooks": [
            "SessionStart": quick, "UserPromptSubmit": quick, "Stop": quick, "StopFailure": quick,
            "Notification": quick, "SubagentStart": quick, "SubagentStop": quick,
            "PreToolUse": [hook(600)], "PermissionRequest": [hook(600)], "PostToolUse": quick,
        ],
    ]
    let dir = EntermPaths.hooksDir
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let settingsURL = dir.appendingPathComponent("claude-settings.json")
    let mcpURL = dir.appendingPathComponent("claude-mcp.json")
    if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]) { try? data.write(to: settingsURL, options: .atomic) }
    let mcp: [String: Any] = ["mcpServers": ["enterm": ["command": selfPath, "args": ["mcp"]]]]
    if let data = try? JSONSerialization.data(withJSONObject: mcp) { try? data.write(to: mcpURL, options: .atomic) }
    return (settingsURL.path, mcpURL.path)
}

// MARK: Other programs: everything lives in Enterm's own folder and reaches the program through an argument or a variable.

func writeJSON(_ object: Any, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]) { try? data.write(to: url, options: .atomic) }
}

func writeGeminiSettings() -> String {
    func hook(_ matcher: String? = nil) -> [[String: Any]] {
        var entry: [String: Any] = ["hooks": [["type": "command", "command": hookCommand("gemini"), "timeout": 5000]]]
        if let matcher { entry["matcher"] = matcher }
        return [entry]
    }
    let settings: [String: Any] = [
        "hooks": ["SessionStart": hook(), "BeforeAgent": hook(), "BeforeTool": hook("*"), "AfterAgent": hook(), "Notification": hook()],
        "mcpServers": ["enterm": ["command": selfPath, "args": ["mcp"]]],
    ]
    let url = EntermPaths.hooksDir.appendingPathComponent("gemini-system.json")
    writeJSON(settings, to: url)
    return url.path
}

func writeOpencodePlugin() -> String {
    let dir = EntermPaths.hooksDir.appendingPathComponent("opencode", isDirectory: true)
    let plugins = dir.appendingPathComponent("plugins", isDirectory: true)
    try? FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
    // Each event becomes one `enterm event` call, the way the shell integration reports a command.
    let script = """
    // Written by Enterm. Reports the session's state to the Enterm window; changes nothing in opencode.
    const enterm = \(String(data: try! JSONSerialization.data(withJSONObject: [selfPath], options: []), encoding: .utf8)!)[0]
    export const Enterm = async ({ $ }) => {
      const send = async (kind, text = "") => { try { await $`${enterm} event ${kind} ${text}`.quiet() } catch {} }
      return {
        event: async ({ event }) => {
          const p = event.properties || {}
          if (event.type === "session.status") await send(p.status && p.status.type === "idle" ? "stop" : "working")
          else if (event.type === "session.idle") await send("stop")
          else if (event.type === "permission.asked" || event.type === "permission.updated") await send("ask")
          else if (event.type === "permission.replied") await send("working")
          else if (event.type === "session.error") await send("error", (p.error && p.error.name) || "")
          else if (event.type === "session.updated" && p.info && p.info.title) await send("title", p.info.title)
        },
      }
    }
    """
    try? script.write(to: plugins.appendingPathComponent("enterm.js"), atomically: true, encoding: .utf8)
    return dir.path
}

func writeCopilotPlugin() -> (plugin: String, mcp: String) {
    let dir = EntermPaths.hooksDir.appendingPathComponent("copilot-plugin", isDirectory: true)
    writeJSON(["name": "enterm", "description": "Enterm durum bildirimi", "version": EntermVersion.current], to: dir.appendingPathComponent("plugin.json"))
    let command: [String: Any] = ["type": "command", "bash": hookCommand("copilot"), "timeoutSec": 10]
    let events = ["sessionStart", "userPromptSubmitted", "preToolUse", "postToolUse", "notification", "agentStop", "errorOccurred"]
    writeJSON(["version": 1, "hooks": Dictionary(uniqueKeysWithValues: events.map { ($0, [command]) })], to: dir.appendingPathComponent("hooks.json"))
    let mcp = EntermPaths.hooksDir.appendingPathComponent("copilot-mcp.json")
    writeJSON(["mcpServers": ["enterm": ["type": "local", "command": selfPath, "args": ["mcp"], "tools": ["*"]]]], to: mcp)
    return (dir.path, mcp.path)
}

func writeCursorPlugin() -> String {
    let dir = EntermPaths.hooksDir.appendingPathComponent("cursor-plugin", isDirectory: true)
    writeJSON(["name": "enterm", "description": "Enterm durum bildirimi", "version": EntermVersion.current], to: dir.appendingPathComponent(".cursor-plugin/plugin.json"))
    writeJSON(["mcpServers": ["enterm": ["command": selfPath, "args": ["mcp"]]]], to: dir.appendingPathComponent("mcp.json"))
    let command: [String: Any] = ["command": hookCommand("cursor")]
    writeJSON(["version": 1, "hooks": ["beforeSubmitPrompt": [command], "afterAgentResponse": [command], "stop": [command]]],
              to: dir.appendingPathComponent("hooks/hooks.json"))
    return dir.path
}

/// Gemini, Copilot and Cursor name their events differently; each becomes one of Enterm's few states.
/// They only report. Approvals stay in the program's own prompt, so a wrong guess here can never allow anything.
func handleOtherHook(_ program: String) {
    let input = readInput()
    guard !sessionID.isEmpty else { return }
    let name = (input["hook_event_name"] as? String) ?? (input["hookEventName"] as? String) ?? (input["hook_event"] as? String)
        ?? environment["GROK_HOOK_EVENT"] ?? ""
    var event = AgentEvent(sessionID: sessionID, kind: "")
    event.toolSessionID = (input["session_id"] as? String) ?? (input["sessionId"] as? String) ?? (input["conversation_id"] as? String)
    event.transcriptPath = (input["transcript_path"] as? String) ?? (input["transcriptPath"] as? String)
    let notification = ((input["notification_type"] as? String) ?? (input["notificationType"] as? String) ?? "").lowercased()
    switch name.lowercased() {
    case "sessionstart": event.kind = "start"
    case "beforeagent", "userpromptsubmitted", "userpromptsubmit", "beforesubmitprompt": event.kind = "prompt"
    case "beforetool", "pretooluse", "posttooluse": event.kind = "working"
    case "afteragent", "agentstop", "stop", "afteragentresponse": event.kind = "stop"
    case "erroroccurred", "stopfailure": event.kind = "error"
    case "notification":
        if notification.contains("permission") { event.kind = "ask" }
        else if notification.contains("idle") || notification.contains("completed") { event.kind = "stop" }
        else { return }
    default: return
    }
    sendEvent(event)
    // Cursor waits for an answer before sending a prompt; this one lets it through unchanged.
    if program == "cursor", name.lowercased() == "beforesubmitprompt" { output(["continue": true]) }
}

func userStatusLine() -> String? {
    let dir = environment["CLAUDE_CONFIG_DIR"] ?? (NSHomeDirectory() + "/.claude")
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: dir + "/settings.json")),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let line = object["statusLine"] as? [String: Any], let command = line["command"] as? String else { return nil }
    return command
}

func wrap(_ tool: String, _ rest: [String]) -> Never {
    guard let path = findInPath(tool) else {
        FileHandle.standardError.write(Data("\(tool): command not found\n".utf8))
        exit(127)
    }
    var argv = [tool]
    var extra: [String: String] = [:]
    let removed = ["ENTERM_MODEL", "ENTERM_EFFORT", "ENTERM_ADVISOR", "ENTERM_STARTUP"]
    let wantsHelp = rest.contains { ["--help", "-h", "--version", "-v", "update", "install", "doctor", "mcp", "auth", "login", "logout"].contains($0) }
    if !wantsHelp {
        switch tool {
        case "claude":
            let files = writeClaudeFiles()
            if !rest.contains("--settings") { argv += ["--settings", files.settings] }
            if !rest.contains("--mcp-config") { argv += ["--mcp-config", files.mcp] }
            // The preset skills that are on, from inside Enterm, for this session only.
            let packs = JSONStore.load(AppSettings.self, from: EntermPaths.settingsFile)?.skillPacks ?? []
            argv += SkillPack.pluginArguments(enabled: packs, root: SkillPack.root(executable: selfPath, environment: environment))
            if !rest.contains("--model"), let model = environment["ENTERM_MODEL"], !model.isEmpty { argv += ["--model", model] }
            if !rest.contains("--effort"), let effort = environment["ENTERM_EFFORT"], !effort.isEmpty { argv += ["--effort", effort] }
            if let advisor = environment["ENTERM_ADVISOR"], !advisor.isEmpty { argv += ["--advisor", advisor] }
            if let line = userStatusLine() { extra["ENTERM_USER_STATUSLINE"] = line }
        case "codex":
            argv += ["-c", "notify=[\"\(selfPath)\",\"notify-codex\"]"]
            argv += ["-c", "mcp_servers.enterm.command=\"\(selfPath)\"", "-c", "mcp_servers.enterm.args=[\"mcp\"]"]
            // Codex asks the user to trust hooks in its own /hooks screen. Until then they simply do not run.
            let hook = "[{hooks=[{type=\"command\",command=\"'\(selfPath)' hook codex\"}]}]"
            for name in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SubagentStart", "SubagentStop"] {
                argv += ["-c", "hooks.\(name)=\(hook)"]
            }
        case "agy":
            confirmAntigravityOnce()
        case "gemini":
            // Gemini reads one extra settings layer from an environment variable. If the machine already has an
            // administrator's system settings file, that file stays in charge and Enterm only watches the screen.
            let system = "/Library/Application Support/GeminiCli/settings.json"
            if environment["GEMINI_CLI_SYSTEM_SETTINGS_PATH"] == nil, !FileManager.default.fileExists(atPath: system) {
                extra["GEMINI_CLI_SYSTEM_SETTINGS_PATH"] = writeGeminiSettings()
            }
        case "opencode":
            // A plugin folder of Enterm's own and the bridge as an inline override; a folder the person set wins.
            if environment["OPENCODE_CONFIG_DIR"] == nil { extra["OPENCODE_CONFIG_DIR"] = writeOpencodePlugin() }
            if environment["OPENCODE_CONFIG_CONTENT"] == nil {
                let content: [String: Any] = ["mcp": ["enterm": ["type": "local", "command": [selfPath, "mcp"], "enabled": true]]]
                if let data = try? JSONSerialization.data(withJSONObject: content) { extra["OPENCODE_CONFIG_CONTENT"] = String(decoding: data, as: UTF8.self) }
            }
        case "copilot":
            let files = writeCopilotPlugin()
            if !rest.contains("--plugin-dir") { argv += ["--plugin-dir", files.plugin] }
            argv += ["--additional-mcp-config", "@" + files.mcp]
        case "cursor-agent":
            if !rest.contains("--plugin-dir") { argv += ["--plugin-dir", writeCursorPlugin()] }
        default:
            break
        }
    }
    argv += rest
    execute(path, argv, extraEnv: extra, removeEnv: removed)
}

/// Antigravity's terms count usage as consent to product improvement. The user reads that once per folder.
func confirmAntigravityOnce() {
    let cwd = FileManager.default.currentDirectoryPath
    let file = EntermPaths.support.appendingPathComponent("antigravity-acknowledged.json")
    var folders = JSONStore.load([String].self, from: file) ?? []
    guard !folders.contains(cwd) else { return }
    print("\nAntigravity Açılmadan Önce Bilin")
    print("Resmi belgeye göre bu programı kullanmak, konuşma verilerinin ürün geliştirmede kullanılmasına onay sayılır.")
    print("Programın kendi ayarından kapatılabilir. Bu klasörde bir kez sorulur. Enterm bu veriyi görmez, göndermez.")
    print("\nAnladım, Aç: Enter    Vazgeç: başka bir tuş ve Enter")
    let answer = readLine() ?? "x"
    guard answer.isEmpty else { exit(0) }
    folders.append(cwd)
    JSONStore.save(folders, to: file)
}

// MARK: Hooks

func askService(_ event: AgentEvent, op: String, timeout: TimeInterval) -> String? {
    var message = WireMessage(op: op)
    message.event = event
    return WireSocket.send(message, waitForReply: true, timeout: timeout)?.decision
}

func handleClaudeHook() {
    let input = readInput()
    guard !sessionID.isEmpty, let name = input["hook_event_name"] as? String else { return }
    var event = AgentEvent(sessionID: sessionID, kind: "")
    event.toolSessionID = input["session_id"] as? String
    event.transcriptPath = input["transcript_path"] as? String
    switch name {
    case "SessionStart":
        event.kind = "start"
        event.model = input["model"] as? String
        sendEvent(event)
    case "UserPromptSubmit":
        event.kind = "prompt"
        sendEvent(event)
    case "Stop":
        event.kind = "stop"
        event.text = input["last_assistant_message"] as? String
        // The program's own title, from the end of its transcript. Costs a file read, no model call.
        event.title = event.transcriptPath.flatMap { SessionTitles.tail(of: $0) }.flatMap(SessionTitles.claude(transcript:))
        sendEvent(event)
    case "StopFailure":
        let kind = input["error"] as? String ?? ""
        event.kind = kind == "rate_limit" ? "limit" : "error"
        event.errorKind = kind
        event.text = (input["error_details"] as? String) ?? (input["last_assistant_message"] as? String)
        sendEvent(event)
    case "Notification":
        let type = input["notification_type"] as? String ?? ""
        event.kind = type == "permission_prompt" ? "ask" : (type == "idle_prompt" ? "wait" : "note")
        sendEvent(event)
    case "SubagentStart":
        event.kind = "subStart"
        event.agentID = input["agent_id"] as? String
        event.agentType = input["agent_type"] as? String
        sendEvent(event)
    case "SubagentStop":
        event.kind = "subStop"
        event.agentID = input["agent_id"] as? String
        sendEvent(event)
    case "PreToolUse":
        handlePreToolUse(input, base: event)
    case "PermissionRequest":
        handlePermissionRequest(input, base: event)
    case "PostToolUse":
        // Only a heavy command holds the queue, others must not spend time here.
        let command = (input["tool_input"] as? [String: Any])?["command"] as? String ?? ""
        if HeavyWork.matches(command) {
            var done = WireMessage(op: "heavyDone")
            done.event = event
            _ = WireSocket.send(done)
        }
        // The program went on after a question it asked itself.
        event.kind = "working"
        sendEvent(event)
    default:
        break
    }
}

func preToolOutput(_ decision: String, reason: String) {
    output(["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": decision, "permissionDecisionReason": reason]])
}

func handlePreToolUse(_ input: [String: Any], base: AgentEvent) {
    let tool = input["tool_name"] as? String ?? ""
    let toolInput = input["tool_input"] as? [String: Any] ?? [:]
    // Subagents started by an agent cannot write to the team.
    if input["agent_id"] != nil, tool.hasPrefix("mcp__enterm__"), tool != "mcp__enterm__ajan_listesi" {
        preToolOutput("deny", reason: "Alt ajanlar ekibe mesaj yazamaz.")
        return
    }
    if tool.hasPrefix("mcp__enterm__") { return }
    if let loop = LoopText.from(tool: tool, input: toolInput) {
        var note = base
        note.kind = "loop"
        note.text = loop?.summary
        note.nextRun = loop?.next
        sendEvent(note)
    }
    let classified = PermissionClassifier.classify(tool: tool, input: toolInput)
    var activity = base
    activity.kind = "working"
    activity.text = classified.summary
    sendEvent(activity)
    if classified.category == .editFiles, let path = toolInput["file_path"] as? String {
        var lock = base
        lock.kind = "lock"
        lock.text = path
        if askService(lock, op: "lock", timeout: 2) == "deny" {
            preToolOutput("deny", reason: "Bu dosyada başka bir ajan çalışıyor. Aynı dosyaya iki ajan aynı anda dokunmaz.")
            return
        }
    }
    let book = PermissionBook.load()
    if !book.card(for: sessionID).passThrough {
        let mode = book.decision(sessionID: sessionID, category: classified.category, host: classified.host)
        switch mode {
        case .deny:
            preToolOutput("deny", reason: "Enterm yetki kartı: \(classified.category.title) kapalı.")
            return
        case .ask where [.ssh, .pushDeploy, .deleteFiles, .internet].contains(classified.category):
            var request = base
            request.kind = "approval"
            request.tool = tool
            request.text = classified.summary
            request.errorKind = classified.category.rawValue
            request.model = classified.host
            switch askService(request, op: "approval", timeout: 590) {
            case "allow": preToolOutput("allow", reason: "Kullanıcı Enterm'de izin verdi.")
            case "deny": preToolOutput("deny", reason: "Kullanıcı Enterm'de reddetti.")
            default: break
            }
        default:
            break
        }
    }
    // After the permissions, a heavy command waits for its turn. If the wait runs out it still goes ahead.
    if classified.category == .command, HeavyWork.matches(classified.summary) {
        var heavy = base
        heavy.kind = "heavy"
        heavy.text = classified.summary
        var message = WireMessage(op: "heavyStart")
        message.event = heavy
        _ = WireSocket.send(message, waitForReply: true, timeout: 570)
    }
}

func handlePermissionRequest(_ input: [String: Any], base: AgentEvent) {
    let tool = input["tool_name"] as? String ?? ""
    let toolInput = input["tool_input"] as? [String: Any] ?? [:]
    if tool.hasPrefix("mcp__enterm__") {
        permissionOutput(allow: true)
        return
    }
    // With the program deciding, the card waits a short while and then its own prompt takes over.
    let free = PermissionBook.load().card(for: sessionID).passThrough
    if free, JSONStore.load(AppSettings.self, from: EntermPaths.settingsFile)?.oneClickApprovals != true { return }
    let classified = PermissionClassifier.classify(tool: tool, input: toolInput)
    var request = base
    request.kind = "approval"
    request.tool = tool
    request.text = classified.summary
    request.errorKind = classified.category.rawValue
    request.model = classified.host
    switch askService(request, op: "approval", timeout: free ? 45 : 590) {
    case "allow": permissionOutput(allow: true)
    case "deny": permissionOutput(allow: false)
    default: break
    }
}

func permissionOutput(allow: Bool) {
    var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
    if !allow { decision["message"] = "Kullanıcı Enterm'de reddetti." }
    output(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
}

func handleAntigravityHook() {
    let input = readInput()
    guard !sessionID.isEmpty else { return }
    var event = AgentEvent(sessionID: sessionID, kind: "working")
    event.toolSessionID = input["conversationId"] as? String
    event.transcriptPath = input["transcriptPath"] as? String
    event.model = input["modelName"] as? String
    event.kind = input["fullyIdle"] as? Bool == true ? "stop" : "working"
    sendEvent(event)
    // An empty answer lets the tool run under the program's own rules.
}

func handleStatusLine() {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    if !sessionID.isEmpty {
        var event = AgentEvent(sessionID: sessionID, kind: "status")
        if let model = input["model"] as? [String: Any] { event.model = model["display_name"] as? String }
        if let effort = input["effort"] as? [String: Any] { event.effort = effort["level"] as? String }
        if let cost = input["cost"] as? [String: Any] { event.costUSD = cost["total_cost_usd"] as? Double }
        if let window = input["context_window"] as? [String: Any] {
            event.inputTokens = window["total_input_tokens"] as? Int
            event.outputTokens = window["total_output_tokens"] as? Int
            event.contextPercent = (window["used_percentage"] as? NSNumber)?.intValue
            if let usage = window["current_usage"] as? [String: Any] {
                let parts = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { usage[$0] as? Int }
                event.contextTokens = parts.reduce(0, +)
            }
        }
        if let limits = input["rate_limits"] as? [String: Any] {
            func window(_ key: String) -> LimitWindow? {
                guard let value = limits[key] as? [String: Any], let used = (value["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
                let resets = (value["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                return LimitWindow(usedPercent: used, resetsAt: resets)
            }
            event.limit = LimitSnapshot(fiveHour: window("five_hour"), sevenDay: window("seven_day"), seenAt: Date())
        }
        sendEvent(event)
    }
    // The user's own status line keeps working on top of ours.
    if let command = environment["ENTERM_USER_STATUSLINE"], !command.isEmpty {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardInput = pipe
        try? process.run()
        pipe.fileHandleForWriting.write(data)
        try? pipe.fileHandleForWriting.close()
        process.waitUntilExit()
    }
}

func handleCodexNotify() {
    guard arguments.count >= 2, !sessionID.isEmpty,
          let object = try? JSONSerialization.jsonObject(with: Data(arguments[1].utf8)) as? [String: Any],
          object["type"] as? String == "agent-turn-complete" else { return }
    var event = AgentEvent(sessionID: sessionID, kind: "stop")
    event.text = object["last-assistant-message"] as? String
    event.toolSessionID = object["thread-id"] as? String
    if let thread = event.toolSessionID {
        let home = environment["CODEX_HOME"] ?? (NSHomeDirectory() + "/.codex")
        event.title = SessionTitles.tail(of: home + "/session_index.jsonl").flatMap { SessionTitles.codex(index: $0, thread: thread) }
    }
    sendEvent(event)
}

switch arguments.first {
case "event":
    guard arguments.count >= 2, !sessionID.isEmpty else { exit(0) }
    var event = AgentEvent(sessionID: sessionID, kind: arguments[1])
    event.text = arguments.count >= 3 && !arguments[2].isEmpty ? arguments[2] : nil
    // A title from a plugin is a title, not a state.
    if event.kind == "title" { event.title = SessionTitles.clean(event.text) }
    sendEvent(event)
case "wrap":
    guard arguments.count >= 2 else { exit(2) }
    wrap(arguments[1], Array(arguments.dropFirst(2)))
case "hook":
    switch arguments.dropFirst().first {
    case "claude", "codex": handleClaudeHook()
    case "agy": handleAntigravityHook()
    case .some(let program) where ["gemini", "copilot", "cursor"].contains(program): handleOtherHook(program)
    default: break
    }
case "statusline":
    handleStatusLine()
case "notify-codex":
    handleCodexNotify()
case "notify":
    guard arguments.count >= 2 else {
        FileHandle.standardError.write(Data("Kullanım: enterm notify \"metin\"\n".utf8))
        exit(2)
    }
    var message = WireMessage(op: "notify")
    message.text = arguments.dropFirst().joined(separator: " ")
    message.id = "notify"
    guard WireSocket.send(message, waitForReply: true, timeout: 3) != nil else {
        FileHandle.standardError.write(Data("Enterm çalışmıyor, bildirim iletilmedi.\n".utf8))
        exit(1)
    }
case "mcp":
    MCPServer().run()
case "version", "--version":
    print("enterm \(EntermVersion.current)")
default:
    FileHandle.standardError.write(Data("Kullanım: enterm notify \"metin\" | enterm version\n".utf8))
    exit(2)
}
