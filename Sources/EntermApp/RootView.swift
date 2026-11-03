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
        super.init(frame: .zero)
        for view in [top as NSView, bottom, side, cards] {
            (view as? NSHostingView<TopBar>)?.safeAreaRegions = []
            (view as? NSHostingView<BottomBars>)?.safeAreaRegions = []
            (view as? NSHostingView<DetailPane>)?.safeAreaRegions = []
            (view as? NSHostingView<InlineCards>)?.safeAreaRegions = []
        }
        wantsLayer = true
        layer?.backgroundColor = Theme.palette.bg.cgColor
        addSubview(canvas)
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
            self?.handleKey(event) ?? event
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
        let barHeight: CGFloat = 44
        let foot: CGFloat = model.footVisible ? 32 : 0
        let toolbar: CGFloat = model.toolbarVisible ? 52 : 0
        let sideWidth: CGFloat = model.detailsOpen ? 400 : 0
        top.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        bottom.frame = NSRect(x: 0, y: bounds.height - foot - toolbar, width: bounds.width, height: foot + toolbar)
        bottom.isHidden = foot + toolbar == 0
        side.frame = NSRect(x: bounds.width - sideWidth, y: barHeight, width: sideWidth, height: bounds.height - barHeight - foot)
        side.isHidden = sideWidth == 0
        let canvasRect = NSRect(x: 0, y: barHeight, width: bounds.width - sideWidth, height: bounds.height - barHeight - foot - toolbar)
        if canvas.frame != canvasRect { canvas.frame = canvasRect }
        let cardsHeight: CGFloat = model.notFound == nil ? 0 : 190
        cards.frame = NSRect(x: 24, y: canvasRect.maxY - cardsHeight - 16, width: min(canvasRect.width - 48, 720), height: cardsHeight)
        cards.isHidden = cardsHeight == 0
    }

    override func layout() {
        super.layout()
        layoutBars()
        cover?.frame = bounds
    }

    /// A click anywhere in a box makes it the focused session, terminal area included.
    private func noteClick(_ event: NSEvent) {
        guard event.window === window, cover == nil else { return }
        let point = canvas.convert(event.locationInWindow, from: nil)
        if let box = canvas.boxes.values.first(where: { !$0.isHidden && $0.frame.contains(point) }), box.number != model.focused {
            model.setFocus(box.number)
        }
    }

    // MARK: Keys

    /// Single keys belong to the terminal when it has focus. They only act when no terminal is typing.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { // Esc
            if model.overlay != nil || model.page != nil {
                Commands.perform("escape")
                return nil
            }
            if model.notFound != nil {
                model.notFound = nil
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
    var footVisible: Bool { hasAgents }
    var toolbarVisible: Bool { mode == .canvas && maximized == nil && sessions.count > 1 }

    func refocusTerminal() {
        guard overlay == nil, page == nil, let host = focusedHost, let window = host.window ?? NSApp.keyWindow else { return }
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
