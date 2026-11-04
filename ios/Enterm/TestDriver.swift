#if DEBUG
import EntermCore
import Foundation
import UIKit
import UserNotifications

/// A test hook for the simulator, active only when `ENTERM_TEST` names a command file on the Mac.
/// Debug builds only. It drives the same model the screens drive.
enum TestForm {
    static var values = ""
}

/// Any answer, kept as text for the test log.
struct RawAnswer: Decodable {
    let text: String
    init(from decoder: Decoder) throws {
        text = String(describing: try? decoder.singleValueContainer().decode(AnyCodableShape.self))
    }
}

struct AnyCodableShape: Decodable, CustomStringConvertible {
    var description = "answer"
    init(from decoder: Decoder) throws {}
}

@MainActor
enum TestDriver {
    private static func parseRoute(_ text: String) -> PhoneRoute? {
        let bits = text.split(separator: " ").map(String.init)
        let number = bits.count > 1 ? UInt32(bits[1]) : nil
        switch bits.first {
        case "details": return number.map { .details($0) }
        case "changes": return number.map { .changes($0) }
        case "diff": return number.map { .diff($0, bits[2]) }
        case "browser": return number.map { .browser($0) }
        case "linkTarget": return number.map { .linkTarget($0) }
        case "linkPermission": return number.map { .linkPermission($0, UInt32(bits[2]) ?? 0) }
        case "messages": return number.map { .messages($0) }
        case "card": return number.map { .card($0) }
        case "limit": return number.map { .limit($0) }
        case "accounts": return .accounts
        case "accountAdd": return .accountAdd
        case "cost": return .cost
        case "power": return .power
        case "teamStart": return .teamStart
        case "teamRoster": return .teamRoster
        case "teamDecisions": return .teamDecisions
        case "newOptions": return .newOptions
        case "install": return ToolKind(rawValue: bits[1]).map { .install($0) }
        default: return nil
        }
    }

    static var lastNotice: PhoneNotice?

    static func start() {
        guard let path = ProcessInfo.processInfo.environment["ENTERM_TEST"] else { return }
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in poll(path) }
        }
    }

    private static func poll(_ path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty else { return }
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
        let model = PhoneModel.shared
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let rest = parts.count > 1 ? parts[1] : ""
            switch parts.first {
            case "pair": _ = model.read(code: rest)
            case "scan": model.pairing = .scanning
            case "confirm": model.confirmNumber()
            case "tab": model.tab = Int(rest) ?? 0
            case "open": model.openSession = UInt32(rest)
            case "back": model.openSession = nil
            case "type":
                if let number = model.openSession { model.input(number, Data(rest.replacingOccurrences(of: "\\r", with: "\r").utf8)) }
            case "new":
                Task { await model.start(tool: ToolKind(rawValue: rest) ?? .terminal) }
            case "route":
                if let route = parseRoute(rest) { model.route.append(route) }
            case "pop":
                if !model.route.isEmpty { model.route.removeLast() }
            case "clearroutes": model.route = []
            case "form": TestForm.values = rest
            case "call":
                let bits = rest.split(separator: " ").map(String.init)
                var args: [String: String] = [:]
                for bit in bits.dropFirst(2) {
                    let kv = bit.split(separator: "=", maxSplits: 1).map(String.init)
                    if kv.count == 2 { args[kv[0]] = kv[1].replacingOccurrences(of: "+", with: " ") }
                }
                let number = bits.count > 1 ? UInt32(bits[1]) : nil
                Task {
                    let result = await model.call(PhoneCall(bits[0], number: number, args: args), as: RawAnswer.self)
                    let text: String
                    switch result {
                    case .success(let answer): text = "ok " + answer.text
                    case .failure(let problem): text = "hata " + problem.message
                    }
                    try? text.write(toFile: "/tmp/et/ios-call.txt", atomically: true, encoding: .utf8)
                }
            case "allow":
                if let approval = model.waitingApprovals.first?.pendingApproval { model.decide(id: approval.id, decision: "allow") }
            case "deny":
                if let approval = model.waitingApprovals.first?.pendingApproval { model.decide(id: approval.id, decision: "deny") }
            case "token": model.receivedToken(rest)
            case "unpair": model.unpair()
            case "seal":
                if let key = model.peer?.key, let plain = try? JSONEncoder().encode(PhoneNotice(kind: "approval", title: "◆ deneme", body: "ssh deploy@staging", number: 1, approvalID: "x")),
                   let sealed = TunnelCrypto.sealNotification(plain, pairKey: key) {
                    try? sealed.write(toFile: rest, atomically: true, encoding: .utf8)
                }
            case "state":
                var lines = ["pairing=\(model.pairing) connection=\(model.connection) peer=\(model.peer?.name ?? "-") tab=\(model.tab) open=\(String(describing: model.openSession))"]
                for info in model.sessions { lines.append("\(info.number) \(info.tool.rawValue) \(info.status.rawValue) approval=\(info.pendingApproval?.summary ?? "-")") }
                if let number = model.openSession {
                    let view = model.host(for: number).view
                    lines.append("view=\(Int(view.bounds.width))x\(Int(view.bounds.height))")
                }
                lines.append("notice=\(String(describing: lastNotice))")
                try? lines.joined(separator: "\n").write(toFile: rest, atomically: true, encoding: .utf8)
            default: break
            }
        }
    }
}
#endif
