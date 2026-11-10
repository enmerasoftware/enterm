import EntermCore
import SwiftTerm
import SwiftUI
import UIKit

/// One session's terminal. Bytes come from the Mac, keystrokes go back.
final class PhoneTerminal: NSObject, TerminalViewDelegate {
    let number: UInt32
    let view: TerminalView
    private var replaying = false
    /// The Mac window's columns and rows. The phone draws exactly this grid and scrolls over it,
    /// so the Mac never narrows and the text here keeps its size.
    private(set) var grid: (cols: Int, rows: Int)?
    /// What SwiftTerm last laid out, to learn the cell size from.
    private var drawn = (cols: 0, rows: 0)
    var onLayout: (() -> Void)?
    var onOutput: (() -> Void)?

    init(number: UInt32) {
        self.number = number
        view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        super.init()
        view.terminalDelegate = self
        applyTheme(dark: UserDefaults.standard.string(forKey: "theme") != "light")
        // Fixed: the grid comes from the Mac, a size that follows the system setting would only make it scroll more.
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
            view.feed(byteArray: ArraySlice([UInt8](ZshMark.strip(bytes))))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.replaying = false }
        } else {
            view.feed(byteArray: ArraySlice(bytes))
        }
        onOutput?()
    }

    func setGrid(cols: Int, rows: Int) {
        guard cols > 1, rows > 1 else { return }
        grid = (cols, rows)
        onLayout?()
    }

    /// The frame that holds the Mac's grid at this font, or nil until both are known.
    func gridSize() -> CGSize? {
        guard let grid, drawn.cols > 0, drawn.rows > 0 else { return nil }
        let optimal = view.getOptimalFrameSize()
        let cellWidth = optimal.width / CGFloat(drawn.cols)
        let cellHeight = optimal.height / CGFloat(drawn.rows)
        // A point over the exact size, never a whole cell, so SwiftTerm counts the same columns and rows.
        return CGSize(width: ceil(CGFloat(grid.cols) * cellWidth) + 1, height: ceil(CGFloat(grid.rows) * cellHeight) + 1)
    }

    func press(_ text: String) {
        Task { @MainActor in PhoneModel.shared.input(number, Data(text.utf8)) }
    }

    /// Nothing goes to the Mac: only its window sizes a session.
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        let first = drawn.cols == 0
        drawn = (newCols, newRows)
        if first { onLayout?() }
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

/// The Mac's grid on a surface that scrolls both ways. It follows the newest line unless the person scrolled away.
final class TerminalScroller: UIScrollView, UIScrollViewDelegate {
    let terminal: PhoneTerminal
    private var following = true

    init(terminal: PhoneTerminal) {
        self.terminal = terminal
        super.init(frame: .zero)
        delegate = self
        backgroundColor = terminal.view.backgroundColor
        alwaysBounceHorizontal = false
        showsHorizontalScrollIndicator = true
        terminal.view.translatesAutoresizingMaskIntoConstraints = true
        addSubview(terminal.view)
        terminal.onLayout = { [weak self] in self?.setNeedsLayout() }
        terminal.onOutput = { [weak self] in self?.follow() }
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 8
        // Before the Mac's size arrives the terminal fills the screen; nothing is sent back either way.
        let size = terminal.gridSize() ?? CGSize(width: max(bounds.width - inset * 2, 1), height: max(bounds.height, 1))
        let frame = CGRect(x: inset, y: 0, width: size.width, height: size.height)
        if terminal.view.frame != frame { terminal.view.frame = frame }
        let content = CGSize(width: size.width + inset * 2, height: size.height)
        if contentSize != content {
            contentSize = content
            follow()
        }
    }

    func follow() {
        guard following else { return }
        let bottom = max(0, contentSize.height - bounds.height + adjustedContentInset.bottom)
        if abs(contentOffset.y - bottom) > 0.5 { contentOffset.y = bottom }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isDragging || isDecelerating else { return }
        following = contentOffset.y >= contentSize.height - bounds.height + adjustedContentInset.bottom - 24
    }
}

struct TerminalSurface: UIViewRepresentable {
    let terminal: PhoneTerminal
    func makeUIView(context: Context) -> TerminalScroller {
        TerminalScroller(terminal: terminal)
    }
    func updateUIView(_ view: TerminalScroller, context: Context) {
        terminal.applyTheme(dark: true)
    }
}
