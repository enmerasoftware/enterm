import EntermCore
import Foundation
import SwiftTerm
import SwiftUI
import UIKit
import UserNotifications

/// Screens that open over the tabs, one on top of the other.
enum PhoneRoute: Hashable {
    case details(UInt32)
    case changes(UInt32)
    case diff(UInt32, String)
    case browser(UInt32)
    case linkTarget(UInt32)
    case linkPermission(UInt32, UInt32)
    case messages(UInt32)
    case card(UInt32)
    case limit(UInt32)
    case accounts
    case accountAdd
    case cost
    case power
    case teamStart
    case teamRoster
    case teamDecisions
    case report(String)
    case newOptions
    case install(ToolKind)
}

/// The phone's view of the Mac. Sessions run there, this only shows them.
struct PhoneProblem: Error, Equatable {
    let message: String
}

@MainActor
final class PhoneModel: ObservableObject {
    static let shared = PhoneModel()

    enum Connection: Equatable {
        case connecting
        case connected
        case unreachable(attempt: Int)
        case sleeping(since: Date)
    }
    enum Pairing: Equatable {
        case none
        case scanning
        case connecting
        case compare(String)
        case waitingOther(String)
        case failed(String)
    }

    @Published private(set) var peer: PairedPeer?
    @Published private(set) var connection = Connection.connecting
    @Published private(set) var sessions: [SessionInfo] = []
    @Published private(set) var lastKnownAt: Date?
    @Published var pairing = Pairing.none
    @Published var tab = 0
    @Published var openSession: UInt32?
    @Published var missingProgram: String?
    @Published var route: [PhoneRoute] = []
    @Published var startProblem: String?
    @Published var faceIDForApprovals = UserDefaults.standard.object(forKey: "faceIDForApprovals") as? Bool ?? true {
        didSet { UserDefaults.standard.set(faceIDForApprovals, forKey: "faceIDForApprovals") }
    }

    private var link: TunnelLink?
    private var agent: PairingAgent?
    private var decoder = WireDecoder()
    private var hosts: [UInt32: PhoneTerminal] = [:]
    private var attached = Set<UInt32>()
    private var attempt = 0
    private var pendingDecisions: [(id: String, decision: String)] = []
    private var pushToken: String?
    private var pending: [String: (WireMessage) -> Void] = [:]
    private let linkQueue = DispatchQueue(label: "enterm.link")

    var waitingApprovals: [SessionInfo] { sessions.filter { $0.pendingApproval != nil } }

    private static var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("last-sessions.json")
    }

    init() {
        peer = PeerStore.load()
        if let data = try? Data(contentsOf: Self.cacheFile), let saved = try? JSONDecoder().decode(LastKnown.self, from: data) {
            sessions = saved.sessions
            lastKnownAt = saved.at
        }
    }

    private struct LastKnown: Codable {
        var sessions: [SessionInfo]
        var at: Date
    }

    func start() {
        guard let peer, link == nil else { return }
        let link = TunnelLink(peer: peer, role: .phone, queue: linkQueue)
        link.onState = { state in Task { @MainActor in PhoneModel.shared.linkChanged(state) } }
        link.onData = { data in Task { @MainActor in PhoneModel.shared.received(data) } }
        self.link = link
        link.start()
    }

    func returnedToFront() {
        link?.reconnectNow()
    }

    func retryNow() {
        attempt = 0
        link?.reconnectNow()
    }

    // MARK: Pairing

    func read(code: String) -> Bool {
        guard let offer = PairingOffer(url: code) else {
            pairing = .failed("Bu Bir Enterm Kodu Değil.")
            return false
        }
        begin(offer)
        return true
    }

    private func begin(_ offer: PairingOffer) {
        agent?.cancel()
        pairing = .connecting
        let agent = PairingAgent(answering: offer, name: UIDevice.current.name, queue: linkQueue)
        agent.onStage = { [weak agent] stage in
            let result = agent?.result
            Task { @MainActor in PhoneModel.shared.pairingChanged(stage, result: result) }
        }
        self.agent = agent
        agent.start()
    }

    private func pairingChanged(_ stage: PairingAgent.Stage, result: PairedPeer?) {
        switch stage {
        case .waiting: break
        case .compare(let number): pairing = .compare(number)
        case .confirmed:
            if case .compare(let number) = pairing { pairing = .waitingOther(number) }
        case .finished:
            guard let result else { return }
            guard PeerStore.save(result) else {
                pairing = .failed("Anahtar Bu Telefona Kaydedilemedi.")
                return
            }
            peer = result
            pairing = .none
            agent = nil
            start()
            askForNotifications()
        case .failed:
            if case .none = pairing { return }
            pairing = .failed("Bağlantı Kesildi. Bilgisayarda Yeni Kod Alın.")
        }
    }

    func confirmNumber() { agent?.confirm() }

    func cancelPairing() {
        agent?.cancel()
        agent = nil
        pairing = .none
    }

    /// Forgets the Mac on this phone. Sessions on the Mac go on.
    func unpair() {
        link?.stop()
        link = nil
        PeerStore.clear()
        try? FileManager.default.removeItem(at: Self.cacheFile)
        peer = nil
        sessions = []
        lastKnownAt = nil
        hosts.removeAll()
        attached.removeAll()
        openSession = nil
        connection = .connecting
    }

    // MARK: Link

    private func linkChanged(_ state: TunnelLink.State) {
        switch state {
        case .ready:
            attempt = 0
            connection = .connected
            decoder = WireDecoder()
            attached.removeAll()
            send(WireMessage(op: "hello"))
            if let pushToken { sendToken(pushToken) }
            for host in hosts.keys where host == openSession { attach(host) }
            let decisions = pendingDecisions
            pendingDecisions = []
            decisions.forEach { decide(id: $0.id, decision: $0.decision) }
        case .connecting, .waitingPeer, .rejected:
            if case .sleeping = connection { return }
            attempt += 1
            connection = .unreachable(attempt: attempt)
        }
    }

    private func received(_ data: Data) {
        for frame in decoder.feed(data) {
            switch frame.kind {
            case .json:
                if let message = WireMessage.decode(frame.payload) { handle(message) }
            case .output, .replay:
                if let (number, bytes) = frame.splitSession() {
                    hosts[number]?.show(bytes, replay: frame.kind == .replay)
                }
            default:
                break
            }
        }
    }

    private func handle(_ message: WireMessage) {
        if let id = message.id, let reply = pending.removeValue(forKey: id) {
            reply(message)
            return
        }
        switch message.op {
        case "state":
            sessions = (message.sessions ?? []).filter { $0.status != .exited }
            remember()
        case "session":
            guard let info = message.session else { return }
            if info.status == .exited {
                sessions.removeAll { $0.number == info.number }
                closeLocally(info.number)
            } else if let index = sessions.firstIndex(where: { $0.number == info.number }) {
                sessions[index] = info
            } else {
                sessions.append(info)
            }
            remember()
        case "removed":
            if let number = message.number {
                sessions.removeAll { $0.number == number }
                closeLocally(number)
            }
        case "macSleeping":
            connection = .sleeping(since: Date())
        case "unpaired":
            unpair()
        case "notFound":
            missingProgram = message.text
        default:
            break
        }
    }

    private func closeLocally(_ number: UInt32) {
        hosts[number] = nil
        attached.remove(number)
        if openSession == number { openSession = nil }
    }

    private func remember() {
        lastKnownAt = Date()
        if let data = try? JSONEncoder().encode(LastKnown(sessions: sessions, at: Date())) {
            try? data.write(to: Self.cacheFile, options: .atomic)
        }
    }

    func send(_ message: WireMessage) {
        link?.send(message.frame().encoded())
    }

    // MARK: Sessions

    func host(for number: UInt32) -> PhoneTerminal {
        if let host = hosts[number] { return host }
        let host = PhoneTerminal(number: number)
        hosts[number] = host
        return host
    }

    func attach(_ number: UInt32) {
        guard !attached.contains(number) else { return }
        attached.insert(number)
        host(for: number).prepareForReplay()
        var message = WireMessage(op: "attach")
        message.number = number
        send(message)
    }

    /// Output stops flowing as soon as nobody on the phone looks at it.
    func detach(_ number: UInt32) {
        attached.remove(number)
        var message = WireMessage(op: "detach")
        message.number = number
        send(message)
    }

    func input(_ number: UInt32, _ bytes: Data) {
        link?.send(WireFrame.session(.input, number: number, bytes: bytes).encoded())
    }

    func resize(_ number: UInt32, rows: Int, cols: Int) {
        var message = WireMessage(op: "resize")
        message.number = number
        message.rows = rows
        message.cols = cols
        send(message)
    }

    /// Started by the Mac's own code, so PATH, a copy outside it, the account and the queue work the same.
    func start(tool: ToolKind, name: String = "", folder: String = "", account: String = "", template: String = "", model: String = "", effort: String = "") async {
        let args = ["tool": tool.rawValue, "name": name, "folder": folder, "account": account, "template": template, "model": model, "effort": effort]
        switch await call(PhoneCall("start", args: args), as: PhoneStart.self) {
        case .failure(let problem):
            startProblem = problem.message
        case .success(let result):
            if let missing = result.missingTool {
                route.append(.install(missing))
            } else if result.queued {
                startProblem = "Sırada: Yer Açılınca Kendiliğinden Başlar. Çalışan İş Durmadı."
            } else if let number = result.number {
                tab = 0
                route = []
                openSession = number
            }
        }
    }

    /// A question to the window on the Mac. It may take a moment when the window has to open first.
    func call<T: Decodable>(_ call: PhoneCall, as type: T.Type) async -> Result<T, PhoneProblem> {
        guard connection == .connected else { return .failure(PhoneProblem(message: "Bilgisayara Bağlı Değil")) }
        guard let text = try? String(decoding: JSONEncoder().encode(call), as: UTF8.self) else { return .failure(PhoneProblem(message: "İstek Hazırlanamadı")) }
        var message = WireMessage(op: "appCall")
        message.text = text
        return await withCheckedContinuation { continuation in
            var finished = false
            let finish: (Result<T, PhoneProblem>) -> Void = { result in
                guard !finished else { return }
                finished = true
                continuation.resume(returning: result)
            }
            request(message) { reply in
                if let error = reply.error {
                    finish(.failure(PhoneProblem(message: error)))
                } else if T.self == String.self, let value = (reply.text ?? "") as? T {
                    finish(.success(value))
                } else if let data = reply.text?.data(using: .utf8), let value = try? JSONDecoder().decode(T.self, from: data) {
                    finish(.success(value))
                } else {
                    finish(.failure(PhoneProblem(message: "Yanıt Okunamadı")))
                }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                finish(.failure(PhoneProblem(message: "Bilgisayar Yanıt Vermedi")))
            }
        }
    }

    func close(_ number: UInt32) {
        var message = WireMessage(op: "kill")
        message.number = number
        send(message)
    }

    private func request(_ message: WireMessage, reply: @escaping (WireMessage) -> Void) {
        var message = message
        let id = UUID().uuidString
        message.id = id
        pending[id] = reply
        send(message)
    }

    func decide(id: String, decision: String) {
        guard connection == .connected else {
            pendingDecisions.append((id, decision))
            return
        }
        var message = WireMessage(op: "decide")
        message.id = id
        message.decision = decision
        send(message)
    }

    /// The same name as on the Mac.
    func title(_ info: SessionInfo) -> String {
        SessionLabel.names(sessions)[info.number] ?? info.tool.title
    }

    /// The folder under the name. The Mac's home folder is not this phone's, so it is told by its last part.
    func folder(_ info: SessionInfo) -> String {
        URL(fileURLWithPath: info.cwd).lastPathComponent
    }

    func session(_ number: UInt32) -> SessionInfo? { sessions.first { $0.number == number } }

    // MARK: Notifications

    func askForNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func receivedToken(_ token: String) {
        pushToken = token
        if connection == .connected { sendToken(token) }
    }

    private func sendToken(_ token: String) {
        var message = WireMessage(op: "pushToken")
        message.text = token
        send(message)
    }

    func notice(from userInfo: [AnyHashable: Any]) -> PhoneNotice? {
        guard let sealed = userInfo["enc"] as? String, let peer, let plain = TunnelCrypto.openNotification(sealed, pairKey: peer.key) else { return nil }
        return try? JSONDecoder().decode(PhoneNotice.self, from: plain)
    }
}
