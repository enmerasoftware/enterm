import EntermCore
import SwiftUI
import UserNotifications

@main
struct EntermPhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase
    @StateObject private var model = PhoneModel.shared

    var body: some Scene {
        WindowGroup {
            LockGate()
                .overlay {
                    // The app switcher keeps a picture of the last screen. A terminal must not be in it.
                    if phase != .active { Palette.bg.ignoresSafeArea() }
                }
                .environmentObject(model)
                .preferredColorScheme(model.theme == "light" ? .light : .dark)
                .tint(Palette.fg)
                .onAppear {
                    model.start()
                    LiveStatus.shared.start(model: model)
                }
                .onOpenURL { url in _ = model.read(code: url.absoluteString) }
                .onChange(of: phase) { _, value in
                    if value == .active { model.returnedToFront() }
                    if value == .background { model.wentToBackground() }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
#if DEBUG
        Task { @MainActor in TestDriver.start() }
#endif
        // İzin Ver opens the app, which asks for Face ID, and the answer goes out when the Mac is reachable.
        let allow = UNNotificationAction(identifier: "allow", title: "İzin Ver", options: [.foreground, .authenticationRequired])
        let deny = UNNotificationAction(identifier: "deny", title: "Reddet", options: [.destructive, .foreground])
        let detail = UNNotificationAction(identifier: "detail", title: "Ayrıntıyı Gör", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "APPROVAL", actions: [allow, deny, detail], intentIdentifiers: []),
            UNNotificationCategory(identifier: "EVENT", actions: [detail], intentIdentifiers: []),
        ])
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PhoneModel.shared.receivedToken(token) }
    }

    /// In front of the user the details are opened here, as the extension does in the background.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
#if DEBUG
        await MainActor.run { TestDriver.lastNotice = PhoneModel.shared.notice(from: notification.request.content.userInfo) }
#endif
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        await MainActor.run {
            let model = PhoneModel.shared
            guard let notice = model.notice(from: info) else { return }
            switch action {
            case "allow":
                if let id = notice.approvalID { Approval.allow(id: id) }
            case "deny":
                if let id = notice.approvalID { model.decide(id: id, decision: "deny") }
            default:
                if notice.approvalID != nil { model.tab = 2 } else { model.openSession = notice.number }
            }
        }
    }
}

enum Approval {
    /// Permission is given by the person holding the phone. A phone with no lock set has nothing to ask.
    @MainActor static func allow(id: String) {
        Task {
            if PhoneModel.shared.faceIDForApprovals, !(await PhoneAuth.confirm("İzin vermek için doğrulayın.")) { return }
            PhoneModel.shared.decide(id: id, decision: "allow")
        }
    }
}
