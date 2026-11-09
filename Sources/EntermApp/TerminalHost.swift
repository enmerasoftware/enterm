import AppKit
import CoreText
import EntermCore
import SwiftTerm

/// Keys a Mac user expects at a prompt. A Turkish keyboard needs Option for @ and #, so Option stays a typing key
/// and only these combinations become shell commands.
enum TerminalKeys {
    static func bytes(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> [UInt8]? {
        switch (keyCode, flags) {
        case (123, [.option]), (123, [.option, .numericPad, .function]): return [0x1B, 0x62] // word back
        case (124, [.option]), (124, [.option, .numericPad, .function]): return [0x1B, 0x66] // word forward
        case (51, [.option]): return [0x1B, 0x7F] // delete word
        case (36, [.option]): return [0x1B, 0x0D] // a new line in programs like Claude Code
        case (123, [.command]), (123, [.command, .numericPad, .function]): return [0x01] // start of line
        case (124, [.command]), (124, [.command, .numericPad, .function]): return [0x05] // end of line
        case (51, [.command]): return [0x15] // delete line
        default: return nil
        }
    }
}

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
        // A link or a path underlines under the pointer and opens with a plain click.
        linkHighlightMode = .hover
        changeScrollback(SettingsStore.shared.settings.scrollbackLines)
        registerForDraggedTypes([.fileURL])
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func applyTheme() {
        let theme = TerminalTheme.current
        let settings = SettingsStore.shared.settings
        font = Theme.font(size: settings.fontSize)
        appliedScale = 0
        installColors(theme.swiftTermColors)
        nativeBackgroundColor = theme.backgroundColor
        nativeForegroundColor = theme.foregroundColor
        caretColor = theme.foregroundColor
        layer?.backgroundColor = theme.backgroundColor.cgColor
        let style: CursorStyle
        switch (settings.cursorStyle, settings.cursorBlink) {
        case ("bar", true): style = .blinkBar
        case ("bar", false): style = .steadyBar
        case ("underline", true): style = .blinkUnderline
        case ("underline", false): style = .steadyUnderline
        case (_, false): style = .steadyBlock
        default: style = .blinkBlock
        }
        setCursorStyle(style)
    }

    private var pressLocation: NSPoint?

    override func mouseDown(with event: NSEvent) {
        pressLocation = event.locationInWindow
        super.mouseDown(with: event)
    }

    /// The address or path under a click that did not drag, read from what is on screen.
    private func detectedLink(at event: NSEvent) -> String? {
        guard event.clickCount == 1, !event.modifierFlags.contains(.option), let press = pressLocation,
              hypot(event.locationInWindow.x - press.x, event.locationInWindow.y - press.y) < 3,
              let snapshot = terminalContentSnapshot(region: .viewport), !snapshot.rows.isEmpty else { return nil }
        let characters = [UniChar(0x57)]
        var glyphs = [CGGlyph(0)]
        guard let font = self.font as CTFont?, CTFontGetGlyphsForCharacters(font, characters, &glyphs, 1) else { return nil }
        let scale = window?.backingScaleFactor ?? 2
        let cellWidth = (self.font.advancement(forGlyph: NSGlyph(glyphs[0])).width * scale).rounded() / scale
        let cellHeight = getOptimalFrameSize().height / CGFloat(snapshot.rows.count)
        guard cellWidth > 0, cellHeight > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let column = Int((point.x - bounds.minX) / cellWidth)
        let row = Int((bounds.maxY - point.y) / cellHeight)
        guard snapshot.rows.indices.contains(row), point.x >= bounds.minX else { return nil }
        // A long address continues on the next rows: read the whole wrapped line.
        var first = row
        while first > 0, snapshot.rows[first].isWrapped { first -= 1 }
        var last = row
        while last + 1 < snapshot.rows.count, snapshot.rows[last + 1].isWrapped { last += 1 }
        var line = ""
        var offset: Int?
        for index in first...last {
            for (cellColumn, cell) in snapshot.rows[index].cells.enumerated() {
                if index == row, cellColumn == column { offset = line.count }
                if cell.width > 0 { line += cell.text.isEmpty ? " " : cell.text }
            }
        }
        return offset.flatMap { TerminalLink.find(in: line, at: $0) }
    }

    override func mouseUp(with event: NSEvent) {
        let link = detectedLink(at: event)
        // SwiftTerm would judge plain text against the app's own folder and answer in English.
        // In this mode it leaves such clicks to us; a link a program marked itself still opens with Command.
        linkHighlightMode = .alwaysWithModifier
        super.mouseUp(with: event)
        linkHighlightMode = .hover
        if let link {
            open(link)
            return
        }
        guard SettingsStore.shared.settings.copyOnSelect, let text = getSelection(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let info = AppModel.shared.sessions.first(where: { $0.number == number }) else { return nil }
        let menu = CanvasMenus.session(info)
        if info.tool != .terminal {
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(ActionMenuItem("Yapıştır") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }, at: 0)
            menu.insertItem(ActionMenuItem("Kopyala") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }, at: 0)
        }
        return menu
    }

    /// Hovering gives the keyboard when the person asked for that.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard SettingsStore.shared.settings.focusFollowsPointer, AppModel.shared.overlay == nil, AppModel.shared.page == nil else { return }
        if AppModel.shared.focused != number { AppModel.shared.setFocus(number) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if SettingsStore.shared.settings.focusFollowsPointer {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        }
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

    func sendBytes(_ bytes: [UInt8]) {
        connection?.sendInput(number: number, bytes: Data(bytes))
    }

    /// A picture on the clipboard goes in as a file, which is what these programs read. Text pastes as it always did.
    override func paste(_ sender: Any) {
        if pasteFilesOrImage(from: .general) { return }
        super.paste(sender)
    }

    /// A file or a picture has no text of its own: its path goes in, the way a program like Claude Code reads an image.
    func pasteFilesOrImage(from board: NSPasteboard) -> Bool {
        guard board.string(forType: .string) == nil else { return false }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            typeQuoted(urls.map(\.path))
            return true
        }
        if let image = NSImage(pasteboard: board), let path = Self.saveTemporary(image) {
            typeQuoted([path])
            return true
        }
        return false
    }

    /// As a paste and escaped the way Terminal does on a drop, so programs read it as a path, not as typing.
    private func typeQuoted(_ paths: [String]) {
        pasteText(paths.map(Self.escapedPath).joined(separator: " ") + " ")
    }

    static func escapedPath(_ path: String) -> String {
        var result = ""
        for character in path {
            if character.isLetter || character.isNumber || "/._-+@%:,=~".contains(character) {
                result.append(character)
            } else {
                result.append("\\")
                result.append(character)
            }
        }
        return result
    }

    private static func saveTemporary(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("enterm-yapistir", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("gorsel-\(Int(Date().timeIntervalSince1970)).png")
        return (try? data.write(to: url)) == nil ? nil : url.path
    }

    // A file dropped on a terminal types its path, as in any terminal.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        typeQuoted(urls.map(\.path))
        window?.makeFirstResponder(self)
        return true
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
        open(link)
    }

    private func open(_ link: String) {
        let cwd = AppModel.shared.sessions.first { $0.number == number }?.cwd
        switch TerminalLink.target(link, cwd: cwd, home: NSHomeDirectory()) {
        case .web(let url): NSWorkspace.shared.open(url)
        case .path(let path) where FileManager.default.fileExists(atPath: path): Self.openPath(path)
        case .path: AppModel.shared.hint = "Bu Konum Bulunamadı"
        case nil: break
        }
    }

    /// Text on a screen must not be able to run anything: what could run is only shown in Finder.
    private static func openPath(_ path: String) {
        var isFolder: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
        let url = URL(fileURLWithPath: path)
        let workspace = NSWorkspace.shared
        let opens = isFolder.boolValue ? !workspace.isFilePackage(atPath: path)
            : !FileManager.default.isExecutableFile(atPath: path) && !TerminalLink.runnableExtensions.contains(url.pathExtension.lowercased())
        if opens { workspace.open(url) } else { workspace.activateFileViewerSelecting([url]) }
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
