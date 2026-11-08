import AppKit
import Sparkle

/// Updates come from the GitHub releases. Sparkle reads the appcast there and checks every download
/// against Enmera's public key in Info.plist before it replaces the app.
/// Only a distributed build carries a feed; a local or test build never asks to be replaced.
final class Updates: NSObject {
    static let shared = Updates()
    private var controller: SPUStandardUpdaterController?

    var available: Bool { controller != nil }

    func start() {
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    @objc func check(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }
}
