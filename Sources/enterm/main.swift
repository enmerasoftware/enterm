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
            "PreToolUse": [hook(600)], "PermissionRequest": [hook(600)],
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
        sendEvent(event)
    case "StopFailure":
        let kind = input["error"] as? String ?? ""
        event.kind = kind == "rate_limit" ? "limit" : "error"
        event.text = input["error_details"] as? String
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
    let classified = PermissionClassifier.classify(tool: tool, input: toolInput)
    var activity = base
    activity.kind = "working"
    activity.text = classified.summary
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
    let mode = book.decision(sessionID: sessionID, category: classified.category, host: classified.host)
    switch mode {
    case .deny:
        preToolOutput("deny", reason: "Enterm yetki kartı: \(classified.category.title) kapalı.")
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

func handlePermissionRequest(_ input: [String: Any], base: AgentEvent) {
    let tool = input["tool_name"] as? String ?? ""
    let toolInput = input["tool_input"] as? [String: Any] ?? [:]
    if tool.hasPrefix("mcp__enterm__") {
        permissionOutput(allow: true)
        return
    }
    let classified = PermissionClassifier.classify(tool: tool, input: toolInput)
    var request = base
    request.kind = "approval"
    request.tool = tool
    request.text = classified.summary
    request.errorKind = classified.category.rawValue
    request.model = classified.host
    switch askService(request, op: "approval", timeout: 590) {
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
    sendEvent(event)
}

switch arguments.first {
case "event":
    guard arguments.count >= 3, !sessionID.isEmpty else { exit(0) }
    var event = AgentEvent(sessionID: sessionID, kind: arguments[1])
    event.text = arguments[2]
    sendEvent(event)
case "wrap":
    guard arguments.count >= 2 else { exit(2) }
    wrap(arguments[1], Array(arguments.dropFirst(2)))
case "hook":
    switch arguments.dropFirst().first {
    case "claude", "codex": handleClaudeHook()
    case "agy": handleAntigravityHook()
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
