import EntermCore
import UserNotifications

/// Opens the sealed details on the phone. Apple and the relay only ever see the generic wording.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        if let sealed = request.content.userInfo["enc"] as? String, let peer = PeerStore.load(),
           let plain = TunnelCrypto.openNotification(sealed, pairKey: peer.key),
           let notice = try? JSONDecoder().decode(PhoneNotice.self, from: plain) {
            // The Mac writes in its own language; the phone shows it in the phone's.
            content.title = L(notice.title)
            content.body = L(notice.body)
        }
        contentHandler(content)
    }
}
