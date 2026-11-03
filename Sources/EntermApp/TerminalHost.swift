import AppKit
import EntermCore
import SwiftTerm

/// One live session on screen. The terminal keeps receiving bytes while off screen, but draws nothing there.
final class TerminalHost: TerminalView, TerminalViewDelegate {
    let number: UInt32
    weak var connection: ServiceConnection?
    var onCwd: ((String) -> Void)?
    var onTitle: ((String) -> Void)?
    var onFocus: (() -> Void)?
    private var replaying = false

    init(number: UInt32, connection: ServiceConnection) {
        self.number = number
        self.connection = connection
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        terminalDelegate = self
        optionAsMetaKey = false
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func applyTheme() {
        let palette = Theme.palette
        font = Theme.font(size: SettingsStore.shared.settings.fontSize)
        appliedScale = 0
        nativeBackgroundColor = palette.bg
        nativeForegroundColor = palette.fg
        caretColor = palette.fg
        layer?.backgroundColor = palette.bg.cgColor
    }

    private var appliedScale: CGFloat = 0

    /// Zooming changes the font with the box, so the terminal keeps its rows and columns.
    func applyScaledFont(_ scale: CGFloat) {
        guard scale != appliedScale else { return }
        appliedScale = scale
        font = Theme.font(size: SettingsStore.shared.settings.fontSize * scale)
    }

    func feedOutput(_ data: Data, replay: Bool) {
        if replay {
            // The terminal answers queries found in old output, sometimes a moment later.
            // Those answers must never reach the shell as if they were typed.
            replaying = true
            feed(byteArray: ArraySlice(data))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.replaying = false }
        } else {
            feed(byteArray: ArraySlice(data))
        }
    }

    /// Display Terminal input as if the user typed it.
    func type(_ text: String) {
        connection?.sendInput(number: number, bytes: Data(text.utf8))
    }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        var message = WireMessage(op: "resize")
        message.number = number
        message.rows = newRows
        message.cols = newCols
        connection?.send(message)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        onTitle?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory) else { return }
        let path = url.path.removingPercentEncoding ?? url.path
        if !path.isEmpty { onCwd?(path) }
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        // Terminal answers to old queries must not reach the running program.
        guard !replaying else { return }
        connection?.sendInput(number: number, bytes: Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), url.scheme == "http" || url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    func bell(source: TerminalView) {}

    func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
