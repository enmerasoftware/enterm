#if DEBUG
import EntermCore
import Foundation
import UIKit
import UserNotifications

/// A test hook for the simulator, active only when `ENTERM_TEST` names a command file on the Mac.
/// Debug builds only. It drives the same model the screens drive.
@MainActor
enum TestDriver {
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
            case "new": model.create(tool: ToolKind(rawValue: rest) ?? .terminal, name: "")
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
