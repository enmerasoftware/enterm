import CryptoKit
import Foundation
import Network

/// A WebSocket to the relay. Nothing runs between messages, so an idle link costs nothing.
final class RelaySocket {
    var onOpen: (() -> Void)?
    var onText: ((Data) -> Void)?
    var onBinary: ((Data) -> Void)?
    var onClose: (() -> Void)?
    private var connection: NWConnection?
    private let queue: DispatchQueue

    init(queue: DispatchQueue) { self.queue = queue }

    func open(_ text: String) {
        guard let url = URL(string: text) else {
            queue.async { self.onClose?() }
            return
        }
        let parameters: NWParameters = url.scheme == "wss" ? .tls : .tcp
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        options.maximumMessageSize = 2 * 1024 * 1024
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        let connection = NWConnection(to: .url(url), using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, connection === self.connection else { return }
            switch state {
            case .ready:
                self.onOpen?()
                self.receive(on: connection)
            case .failed, .waiting, .cancelled:
                self.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self, connection === self.connection else { return }
            if error != nil {
                self.finish()
                return
            }
            let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            switch meta?.opcode {
            case .text: if let data { self.onText?(data) }
            case .binary: if let data { self.onBinary?(data) }
            case .close:
                self.finish()
                return
            default: break
            }
            self.receive(on: connection)
        }
    }

    private func finish() {
        guard let current = connection else { return }
        connection = nil
        current.cancel()
        onClose?()
    }

    func close() {
        guard let current = connection else { return }
        connection = nil
        current.cancel()
    }

    func send(binary data: Data) { send(data, opcode: .binary) }

    func send(text value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value) { send(data, opcode: .text) }
    }

    private func send(_ data: Data, opcode: NWProtocolWebSocket.Opcode) {
        let context = NWConnection.ContentContext(identifier: "enterm", metadata: [NWProtocolWebSocket.Metadata(opcode: opcode)])
        connection?.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }
}

/// The encrypted, self-healing link between a paired Mac and phone.
public final class TunnelLink {
    public enum State: Equatable {
        case connecting
        case waitingPeer
        case ready
        /// The other side could not prove it holds the key.
        case rejected
    }

    public var onState: ((State) -> Void)?
    public var onData: ((Data) -> Void)?
    public private(set) var state = State.connecting {
        didSet { if state != oldValue { onState?(state) } }
    }

    private let relay: String
    private let room: String
    private let key: Data
    private let role: TunnelRole
    private let queue: DispatchQueue
    private var socket: RelaySocket?
    private var cipher: TunnelCipher?
    private var ownSalt = Data()
    private var stopped = false
    private var delay: TimeInterval = 1
    private var retry: DispatchWorkItem?

    public init(peer: PairedPeer, role: TunnelRole, queue: DispatchQueue) {
        relay = peer.relay
        room = peer.id
        key = peer.key
        self.role = role
        self.queue = queue
    }

    public func start() { queue.async { self.connect() } }

    public func stop() {
        queue.async {
            self.stopped = true
            self.retry?.cancel()
            self.socket?.close()
            self.socket = nil
        }
    }

    /// The network came back or the app returned to the front: try now rather than at the next delay.
    public func reconnectNow() {
        queue.async {
            guard !self.stopped, self.socket == nil else { return }
            self.delay = 1
            self.retry?.cancel()
            self.connect()
        }
    }

    public func send(_ plain: Data) {
        guard let sealed = cipher?.seal(plain) else { return }
        socket?.send(binary: sealed)
    }

    public func requestPush(token: String, sealed: String, kind: String) {
        socket?.send(text: ["push": ["token": token, "sealed": sealed, "kind": kind]])
    }

    private func connect() {
        guard !stopped else { return }
        cipher = nil
        state = .connecting
        let socket = RelaySocket(queue: queue)
        self.socket = socket
        socket.onOpen = { [weak self, weak socket] in
            guard let self else { return }
            self.delay = 1
            socket?.send(text: ["join": self.room, "role": self.role.rawValue])
        }
        socket.onText = { [weak self] data in self?.control(data) }
        socket.onBinary = { [weak self] data in self?.binary(data) }
        socket.onClose = { [weak self] in self?.lost() }
        socket.open(relay)
    }

    private func lost() {
        socket = nil
        cipher = nil
        guard !stopped else { return }
        if state != .rejected { state = .connecting }
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        retry = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
        delay = min(delay * 2, 60)
    }

    private func control(_ data: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let peer = message["peer"] as? Bool else { return }
        cipher = nil
        guard peer else {
            state = .waitingPeer
            return
        }
        state = .waitingPeer
        ownSalt = TunnelCrypto.randomBytes(32)
        socket?.send(binary: ownSalt)
    }

    private func binary(_ data: Data) {
        guard cipher != nil else {
            guard data.count == 32, !ownSalt.isEmpty else { return }
            let (macSalt, phoneSalt) = role == .mac ? (ownSalt, data) : (data, ownSalt)
            cipher = TunnelCrypto.cipher(pairKey: key, role: role, macSalt: macSalt, phoneSalt: phoneSalt)
            state = .ready
            return
        }
        guard let plain = cipher?.open(data) else {
            cipher = nil
            state = .rejected
            socket?.close()
            socket = nil
            lost()
            return
        }
        onData?(plain)
    }
}

/// One pairing attempt: the QR on the Mac, the camera on the phone, the same six digits on both.
public final class PairingAgent {
    public enum Stage: Equatable {
        case waiting
        case compare(String)
        case confirmed
        case finished(name: String)
        case failed
    }

    public var onStage: ((Stage) -> Void)?
    public private(set) var stage = Stage.waiting {
        didSet { if stage != oldValue { onStage?(stage) } }
    }
    public private(set) var result: PairedPeer?
    public let offer: PairingOffer

    private let role: TunnelRole
    private let queue: DispatchQueue
    private let ownName: String
    private let privateKey = Curve25519.KeyAgreement.PrivateKey()
    private var socket: RelaySocket?
    private var cipher: TunnelCipher?
    private var pairKey = Data()
    private var confirmedHere = false
    private var peerName: String?

    /// On the Mac: makes the code to show.
    public init(relay: String, name: String, queue: DispatchQueue) {
        role = .mac
        ownName = name
        self.queue = queue
        offer = PairingOffer(relay: relay, id: TunnelCrypto.randomRoom(), key: privateKey.publicKey.rawRepresentation)
    }

    /// On the phone: answers a code it has read.
    public init(answering offer: PairingOffer, name: String, queue: DispatchQueue) {
        role = .phone
        ownName = name
        self.queue = queue
        self.offer = offer
    }

    public func start() {
        queue.async {
            let socket = RelaySocket(queue: self.queue)
            self.socket = socket
            socket.onOpen = { [weak self, weak socket] in
                guard let self else { return }
                socket?.send(text: ["join": self.offer.id, "role": self.role.rawValue])
            }
            socket.onText = { [weak self] data in self?.control(data) }
            socket.onBinary = { [weak self] data in self?.binary(data) }
            socket.onClose = { [weak self] in
                guard let self else { return }
                if case .finished = self.stage { return }
                self.stage = .failed
            }
            socket.open(self.offer.relay)
        }
    }

    public func cancel() {
        queue.async {
            self.socket?.close()
            self.socket = nil
        }
    }

    /// The person saw the same number. Each side sends its name only under the new key.
    public func confirm() {
        queue.async {
            guard case .compare = self.stage, !self.confirmedHere else { return }
            self.confirmedHere = true
            self.stage = .confirmed
            if let sealed = self.cipher?.seal(Data(self.ownName.utf8)) { self.socket?.send(binary: sealed) }
            self.finishIfDone()
        }
    }

    private func control(_ data: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        // The phone answers once the Mac is there. A code stays good until the Mac gives up on it.
        if role == .phone, message["peer"] as? Bool == true, cipher == nil {
            socket?.send(binary: privateKey.publicKey.rawRepresentation)
            derive(peerKey: offer.key, offer: offer.key, answer: privateKey.publicKey.rawRepresentation)
        }
        // The peer left after the numbers appeared and before both confirmed.
        if message["peer"] as? Bool == false, cipher != nil {
            if case .finished = stage { return }
            stage = .failed
        }
    }

    private func binary(_ data: Data) {
        if cipher == nil {
            guard role == .mac, data.count == 32 else { return }
            derive(peerKey: data, offer: privateKey.publicKey.rawRepresentation, answer: data)
            return
        }
        guard let plain = cipher?.open(data) else {
            stage = .failed
            return
        }
        peerName = String(decoding: plain, as: UTF8.self)
        finishIfDone()
    }

    private func derive(peerKey: Data, offer: Data, answer: Data) {
        guard let peer = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKey),
              let shared = try? privateKey.sharedSecretFromKeyAgreement(with: peer) else {
            stage = .failed
            return
        }
        let secret = shared.withUnsafeBytes { SymmetricKey(data: Data($0)) }
        pairKey = TunnelCrypto.pairKey(shared: secret, offer: offer, answer: answer)
        cipher = TunnelCrypto.cipher(pairKey: pairKey, role: role, macSalt: offer, phoneSalt: answer)
        stage = .compare(TunnelCrypto.comparisonNumber(shared: secret, offer: offer, answer: answer))
    }

    private func finishIfDone() {
        guard confirmedHere, let peerName else { return }
        result = PairedPeer(name: peerName, relay: offer.relay, key: pairKey)
        stage = .finished(name: peerName)
        socket?.close()
        socket = nil
    }
}
