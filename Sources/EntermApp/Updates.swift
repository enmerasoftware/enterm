import AppKit
import Sparkle

/// Updates come from the GitHub releases. Sparkle reads the appcast there and checks every download
/// against Enmera's public key in Info.plist before it replaces the app.
/// Only a distributed build carries a feed; a local or test build never asks to be replaced.
final class Updates: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = Updates()
    private var controller: SPUStandardUpdaterController?
    /// The version waiting on GitHub, for the mark on the top bar.
    @Published private(set) var waitingVersion: String?

    var available: Bool { controller != nil }

    func start() {
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        // Quietly on launch: it only fills the mark, the question comes when the person asks.
        controller?.updater.checkForUpdateInformation()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        waitingVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        waitingVersion = nil
    }

    @objc func check(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }
}
