import EntermCore
import Foundation

// The small companion command. Sessions call it from the shell integration and from hooks.
// It must stay silent and quick: a hook's stdout can be read as a decision by the program.

let arguments = Array(CommandLine.arguments.dropFirst())
let sessionID = ProcessInfo.processInfo.environment["ENTERM_SESSION_ID"] ?? ""

func sendEvent(_ event: AgentEvent) {
    var message = WireMessage(op: "event")
    message.event = event
    _ = WireSocket.send(message)
}

switch arguments.first {
case "event":
    guard arguments.count >= 3, !sessionID.isEmpty else { exit(0) }
    var event = AgentEvent(sessionID: sessionID, kind: arguments[1])
    event.text = arguments[2]
    sendEvent(event)
case "version", "--version":
    print("enterm \(EntermVersion.current)")
default:
    FileHandle.standardError.write(Data("Kullanım: enterm version\n".utf8))
    exit(2)
}
