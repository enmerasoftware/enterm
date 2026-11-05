import AppKit
import Combine
import EntermCore
import SwiftUI

/// The window content. The canvas and terminals are AppKit; bars, pages and dialogs are SwiftUI.
final class RootView: NSView {
    let model = AppModel.shared
    let canvas: CanvasView
    private let top: NSHostingView<TopBar>
    private let bottom: NSHostingView<BottomBars>
    private let side: NSHostingView<DetailPane>
    private let rail: NSHostingView<SessionRail>
    private var home: NSHostingView<HomeView>?
    private var cover: NSHostingView<CoverContent>?
    private var cards: NSHostingView<InlineCards>
    private var bags = Set<AnyCancellable>()
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var mouseMonitor: Any?

    init() {
        canvas = CanvasView(model: model)
        top = NSHostingView(rootView: TopBar())
        bottom = NSHostingView(rootView: BottomBars())
        side = NSHostingView(rootView: DetailPane())
        cards = NSHostingView(rootView: InlineCards())
        rail = NSHostingView(rootView: SessionRail())
        super.init(frame: .zero)
        rail.safeAreaRegions = []
        for view in [top as NSView, bottom, side, cards] {
            (view as? NSHostingView<TopBar>)?.safeAreaRegions = []
            (view as? NSHostingView<BottomBars>)?.safeAreaRegions = []
            (view as? NSHostingView<DetailPane>)?.safeAreaRegions = []
            (view as? NSHostingView<InlineCards>)?.safeAreaRegions = []
        }
        wantsLayer = true
        layer?.backgroundColor = Theme.palette.surface0.cgColor
        addSubview(canvas)
        addSubview(rail)
        addSubview(top)
        addSubview(bottom)
        addSubview(side)
        addSubview(cards)
        model.onLayoutChange = { [weak self] in
            self?.needsLayout = true
            self?.canvas.relayout(animated: true)
            self?.layoutBars()
        }
        model.onFocusChange = { [weak self] in
            self?.canvas.applyContent()
            self?.model.refocusTerminal()
        }
        model.fitCanvas = { [weak self] in self?.canvas.fit() }
        model.arrangeCanvas = { [weak self] in self?.canvas.arrange() }
        model.$overlay.combineLatest(model.$page)
            .receive(on: RunLoop.main)
            .sink { [weak self] overlay, page in self?.updateCover(overlay: overlay, page: page) }
            .store(in: &bags)
        model.$detailsOpen.combineLatest(model.$notFound)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.needsLayout = true
                self?.model.refocusTerminalLater()
            }
            .store(in: &bags)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // A nil answer means the key was used here. It must not go on to the terminal.
            guard let self else { return event }
            return self.handleKey(event)
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.noteClick(event)
            return event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            VoiceInput.shared.flagsChanged(event)
            return event
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private func updateCover(overlay: Overlay?, page: Page?) {
        if overlay == nil && page == nil {
            cover?.removeFromSuperview()
            cover = nil
            model.refocusTerminalLater()
            return
        }
        if cover == nil {
            let view = NSHostingView(rootView: CoverContent())
            view.safeAreaRegions = []
            addSubview(view)
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            cover = view
        }
    }

    private func layoutBars() {
        let barHeight: CGFloat = model.focusMode ? 28 : 44
        let foot: CGFloat = model.footVisible && !model.focusMode ? 36 : 0
        let toolbar: CGFloat = model.toolbarVisible && !model.focusMode ? 52 : 0
        let sideWidth: CGFloat = model.detailsOpen ? 400 : 0
        updateHome()
        let railWidth: CGFloat = model.railVisible(width: bounds.width) && !model.focusMode ? 200 : 0
        rail.frame = NSRect(x: 0, y: barHeight, width: railWidth, height: bounds.height - barHeight - foot)
        rail.isHidden = railWidth == 0 || home != nil
        top.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        if model.focusMode { top.isHidden = true }
        bottom.frame = NSRect(x: 0, y: bounds.height - foot - toolbar, width: bounds.width, height: foot + toolbar)
        bottom.isHidden = foot + toolbar == 0 || home != nil
        side.frame = NSRect(x: bounds.width - sideWidth, y: barHeight, width: sideWidth, height: bounds.height - barHeight - foot)
        side.isHidden = sideWidth == 0
        let canvasRect = NSRect(x: railWidth, y: barHeight, width: bounds.width - sideWidth - railWidth, height: bounds.height - barHeight - foot - toolbar)
        if canvas.frame != canvasRect { canvas.frame = canvasRect }
        let cardsHeight: CGFloat = model.notFound == nil ? 0 : 216
        // The card sits inside the box of the session it belongs to.
        var anchor = canvasRect
        if let number = model.notFound?.number, let box = canvas.boxes[number], !box.isHidden {
            anchor = canvas.convert(box.frame, to: self)
        }
        cards.frame = NSRect(x: anchor.minX + 12, y: anchor.maxY - cardsHeight - 8, width: min(anchor.width - 24, 720), height: cardsHeight)
        cards.isHidden = cardsHeight == 0
    }

    /// With nothing open the window is the home screen. It costs nothing while a session is open.
    private func updateHome() {
        let nothingOpen = model.sessions.isEmpty && model.state.items.isEmpty
        let empty = model.started && (nothingOpen || model.showHome)
        top.isHidden = model.started && nothingOpen
        // The boxes keep receiving their programs' output behind the home screen, they only leave the screen.
        canvas.isHidden = empty
        if empty, home == nil {
            let view = NSHostingView(rootView: HomeView())
            view.safeAreaRegions = []
            addSubview(view, positioned: .above, relativeTo: rail)
            home = view
        } else if !empty, let view = home {
            view.removeFromSuperview()
            home = nil
        }
        home?.frame = top.isHidden ? bounds : NSRect(x: 0, y: 44, width: bounds.width, height: bounds.height - 44)
    }

    override func layout() {
        super.layout()
        layoutBars()
        (NSApp.delegate as? AppDelegate)?.placeWindowButtons()
        cover?.frame = bounds
    }

    /// A click anywhere in a box makes it the focused session, terminal area included.
    private func noteClick(_ event: NSEvent) {
        guard event.window === window, cover == nil, home == nil else { return }
        let point = canvas.convert(event.locationInWindow, from: nil)
        if let box = canvas.boxes.values.first(where: { !$0.isHidden && $0.frame.contains(point) }), box.number != model.focused {
            model.setFocus(box.number)
        }
    }

    // MARK: Keys

#if ENTERM_TEST_DRIVER
    func debugKey(_ event: NSEvent) -> NSEvent? { handleKey(event) }
#endif

    /// Single keys belong to the terminal when it has focus. They only act when no terminal is typing.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if window?.firstResponder is TerminalHost, let bytes = TerminalKeys.bytes(keyCode: event.keyCode, flags: flags) {
            model.focusedHost?.sendBytes(bytes)
            return nil
        }
        if event.keyCode == 53 { // Esc
            if model.overlay != nil || model.page != nil {
                if model.overlay == nil { model.goBack() } else { Commands.perform("escape") }
                return nil
            }
            if model.notFound != nil {
                model.notFound = nil
                return nil
            }
            if model.showHome, !model.sessions.isEmpty {
                model.showHome = false
                model.onLayoutChange?()
                model.refocusTerminalLater()
                return nil
            }
            return event
        }
        if model.overlay == nil, model.page == nil, flags.isEmpty, !(window?.firstResponder is TerminalHost), !(window?.firstResponder is NSTextView) {
            switch event.charactersIgnoringModifiers {
            case "n": Commands.perform("newSession"); return nil
            case "e": Commands.perform("team"); return nil
            case "0": Commands.perform("fit"); return nil
            case "?": Commands.perform("shortcuts"); return nil
            default: break
            }
        }
        if case .approval(let id)? = model.overlay, flags.isEmpty {
            switch event.charactersIgnoringModifiers {
            case "y": Approvals.decide(id: id, decision: "allow"); return nil
            case "n": Approvals.decide(id: id, decision: "deny"); return nil
            default: break
            }
        }
        if case .installTool(let tool)? = model.overlay, flags.isEmpty, event.keyCode == 36 {
            InstallToolActions.run(tool)
            return nil
        }
        if case .limit? = model.overlay, flags.isEmpty, let text = event.charactersIgnoringModifiers, let digit = Int(text) {
            LimitActions.perform(index: digit - 1)
            return nil
        }
        if model.notFound != nil {
            // The card must never take a command the user is typing: any other key dismisses it.
            if event.keyCode == 36, flags.isEmpty {
                NotFoundActions.primary()
                return nil
            }
            if flags.intersection([.command, .control]).isEmpty { model.notFound = nil }
        }
        return event
    }
}

extension AppModel {
    var footVisible: Bool { hasAgents || toolbarVisible }
    func railVisible(width: CGFloat) -> Bool { toolbarVisible && width >= 900 && SettingsStore.shared.settings.showRail }
    var toolbarVisible: Bool { mode == .canvas && maximized == nil && tileCount > 1 }

    func refocusTerminal() {
        guard overlay == nil, page == nil, !showHome, let number = focused, !chatSessions.contains(number), let host = focusedHost, let window = host.window ?? NSApp.keyWindow else { return }
        if window.firstResponder !== host, host.window != nil { window.makeFirstResponder(host) }
    }

    func refocusTerminalLater() {
        DispatchQueue.main.async { [weak self] in self?.refocusTerminal() }
    }
}

/// Everything that covers the terminals: one dialog or one page at a time.
struct CoverContent: View {
    @ObservedObject var model = AppModel.shared
    var body: some View {
        ZStack {
            if let page = model.page {
                PageRouter(page: page)
            }
            if let overlay = model.overlay {
                OverlayRouter(overlay: overlay)
            }
        }
    }
}
