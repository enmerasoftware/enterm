import EntermCore
import SwiftTerm
import SwiftUI
import UIKit

/// One session's terminal. Bytes come from the Mac, keystrokes go back.
final class PhoneTerminal: NSObject, TerminalViewDelegate {
    let number: UInt32
    let view: TerminalView
    private var replaying = false

    init(number: UInt32) {
        self.number = number
        view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        super.init()
        view.terminalDelegate = self
        applyTheme(dark: UserDefaults.standard.string(forKey: "theme") != "light")
        view.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        // The key row is part of the screen, as drawn.
        view.inputAccessoryView = nil
    }

    /// The terminal stays dark in both themes: SwiftTerm's iOS renderer keeps a black ground here, and dark text on it cannot be read.
    func applyTheme(dark: Bool) {
        let background = Palette.terminalBackground(dark: true)
        view.nativeBackgroundColor = background
        view.nativeForegroundColor = Palette.terminalForeground(dark: true)
        view.backgroundColor = background
        view.superview?.backgroundColor = background
    }

    func prepareForReplay() {
        // A full reset, so old output is not drawn on top of itself.
        view.feed(byteArray: ArraySlice(Array("\u{1b}c".utf8)))
    }

    func show(_ bytes: Data, replay: Bool) {
        if replay {
            // Answers to queries in old output must not reach the program as if they were typed.
            replaying = true
            view.feed(byteArray: ArraySlice(bytes))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.replaying = false }
        } else {
            view.feed(byteArray: ArraySlice(bytes))
        }
    }

    func press(_ text: String) {
        Task { @MainActor in PhoneModel.shared.input(number, Data(text.utf8)) }
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        Task { @MainActor in PhoneModel.shared.resize(number, rows: newRows, cols: newCols) }
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard !replaying else { return }
        let bytes = Data(data)
        Task { @MainActor in PhoneModel.shared.input(number, bytes) }
    }

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), url.scheme == "http" || url.scheme == "https" else { return }
        UIApplication.shared.open(url)
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.string = String(data: content, encoding: .utf8)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func bell(source: TerminalView) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}

struct TerminalSurface: UIViewRepresentable {
    let terminal: PhoneTerminal
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = terminal.view.backgroundColor
        terminal.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal.view)
        NSLayoutConstraint.activate([
            terminal.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            terminal.view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            terminal.view.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {
        terminal.applyTheme(dark: true)
    }
}
