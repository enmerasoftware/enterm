import EntermCore
import Foundation
import Security

/// The paired Mac. The key lives in the keychain, where the notification extension can read it too.
enum PeerStore {
    private static let account = "paired-mac"
    private static let service = "tr.com.enmera.enterm"

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load() -> PairedPeer? {
        var request = query()
        request[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PairedPeer.self, from: data)
    }

    /// False when the key could not be kept: the pairing would not survive the app closing.
    static func save(_ peer: PairedPeer) -> Bool {
        guard let data = try? JSONEncoder().encode(peer) else { return false }
        SecItemDelete(query() as CFDictionary)
        var request = query()
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(query() as CFDictionary)
    }
}
