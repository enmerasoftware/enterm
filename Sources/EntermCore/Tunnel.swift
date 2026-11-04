import CryptoKit
import Foundation

/// What the Mac shows as a QR code. The relay never sees the secret both sides derive from it.
public struct PairingOffer: Equatable {
    public var relay: String
    public var id: String
    public var key: Data

    public init(relay: String, id: String, key: Data) {
        self.relay = relay
        self.id = id
        self.key = key
    }

    public var url: String {
        var parts = URLComponents()
        parts.scheme = "enterm"
        parts.host = "pair"
        parts.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "r", value: relay),
            URLQueryItem(name: "i", value: id),
            URLQueryItem(name: "k", value: key.base64URL),
        ]
        return parts.string ?? ""
    }

    public init?(url text: String) {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "enterm", parts.host == "pair" else { return nil }
        func value(_ name: String) -> String? { parts.queryItems?.first { $0.name == name }?.value }
        guard value("v") == "1", let relay = value("r"), let id = value("i"), let key = value("k").flatMap(Data.init(base64URL:)),
              key.count == 32, TunnelCrypto.isRoom(id), let scheme = URL(string: relay)?.scheme, scheme == "ws" || scheme == "wss" else { return nil }
        self.init(relay: relay, id: id, key: key)
    }
}

public enum TunnelRole: String, Codable {
    case mac
    case phone
}

public enum TunnelCrypto {
    public static func isRoom(_ text: String) -> Bool {
        (32...64).contains(text.count) && text.allSatisfy { "0123456789abcdef".contains($0) }
    }

    public static func randomRoom() -> String { randomBytes(16).map { String(format: "%02x", $0) }.joined() }

    public static func randomBytes(_ count: Int) -> Data {
        Data(SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Array($0) })
    }

    static func derive(_ secret: SymmetricKey, info: String, salt: Data = Data()) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: secret, salt: salt, info: Data(info.utf8), outputByteCount: 32)
    }

    /// Six digits both people compare. A relay in the middle would produce two different numbers.
    public static func comparisonNumber(shared: SymmetricKey, offer: Data, answer: Data) -> String {
        let key = derive(shared, info: "enterm number", salt: offer + answer)
        let value = key.withUnsafeBytes { raw -> UInt32 in raw.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) } }
        let digits = String(format: "%06d", value % 1_000_000)
        return digits.prefix(3) + " " + digits.suffix(3)
    }

    public static func pairKey(shared: SymmetricKey, offer: Data, answer: Data) -> Data {
        derive(shared, info: "enterm pair", salt: offer + answer).rawData
    }

    /// The room a paired Mac and phone meet in. Nothing about the key can be learned from it.
    public static func room(pairKey: Data) -> String {
        derive(SymmetricKey(data: pairKey), info: "enterm room").rawData.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public static func cipher(pairKey: Data, role: TunnelRole, macSalt: Data, phoneSalt: Data) -> TunnelCipher {
        let secret = SymmetricKey(data: pairKey)
        let salt = macSalt + phoneSalt
        let toPhone = derive(secret, info: "enterm mac to phone", salt: salt)
        let toMac = derive(secret, info: "enterm phone to mac", salt: salt)
        return role == .mac ? TunnelCipher(send: toPhone, receive: toMac) : TunnelCipher(send: toMac, receive: toPhone)
    }

    public static func sealNotification(_ plain: Data, pairKey: Data) -> String? {
        let key = derive(SymmetricKey(data: pairKey), info: "enterm notification")
        return (try? ChaChaPoly.seal(plain, using: key))?.combined.base64EncodedString()
    }

    public static func openNotification(_ sealed: String, pairKey: Data) -> Data? {
        guard let data = Data(base64Encoded: sealed), let box = try? ChaChaPoly.SealedBox(combined: data) else { return nil }
        return try? ChaChaPoly.open(box, using: derive(SymmetricKey(data: pairKey), info: "enterm notification"))
    }
}

/// One direction's counter never repeats inside a connection, and each connection has fresh keys.
/// A frame replayed or dropped by the relay fails to open.
public struct TunnelCipher {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0

    public init(send: SymmetricKey, receive: SymmetricKey) {
        sendKey = send
        receiveKey = receive
    }

    private static func nonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
        var bytes = Data(count: 4)
        withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        return try! ChaChaPoly.Nonce(data: bytes)
    }

    public mutating func seal(_ plain: Data) -> Data? {
        defer { sendCounter += 1 }
        guard let box = try? ChaChaPoly.seal(plain, using: sendKey, nonce: Self.nonce(sendCounter)) else { return nil }
        return box.ciphertext + box.tag
    }

    public mutating func open(_ sealed: Data) -> Data? {
        guard sealed.count >= 16 else { return nil }
        let tag = sealed.suffix(16)
        let text = sealed.dropLast(16)
        guard let box = try? ChaChaPoly.SealedBox(nonce: Self.nonce(receiveCounter), ciphertext: text, tag: tag),
              let plain = try? ChaChaPoly.open(box, using: receiveKey) else { return nil }
        receiveCounter += 1
        return plain
    }
}

/// One phone the Mac trusts, or the Mac a phone trusts.
public struct PairedPeer: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var relay: String
    public var key: Data
    public var pairedAt: Date
    public var lastSeen: Date?
    public var pushToken: String?

    public init(name: String, relay: String, key: Data, pairedAt: Date = Date()) {
        id = TunnelCrypto.room(pairKey: key)
        self.name = name
        self.relay = relay
        self.key = key
        self.pairedAt = pairedAt
    }
}

/// What a notification says once the phone has opened it.
public struct PhoneNotice: Codable, Equatable {
    public var kind: String
    public var title: String
    public var body: String
    public var number: UInt32?
    public var approvalID: String?

    public init(kind: String, title: String, body: String, number: UInt32? = nil, approvalID: String? = nil) {
        self.kind = kind
        self.title = title
        self.body = body
        self.number = number
        self.approvalID = approvalID
    }
}

/// The device list as the window sees it. Keys stay in the service.
public struct DeviceSummary: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var pairedAt: Date
    public var lastSeen: Date?
    public var connected: Bool

    public init(id: String, name: String, pairedAt: Date, lastSeen: Date?, connected: Bool) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
        self.lastSeen = lastSeen
        self.connected = connected
    }
}

public extension SymmetricKey {
    var rawData: Data { withUnsafeBytes { Data($0) } }
}

public extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL text: String) {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        self.init(base64Encoded: value)
    }
}
