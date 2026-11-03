import AppKit
import EntermCore

/// One session on the canvas: a header, the live terminal, and for agents a one line footer.
final class SessionBox: NSView {
    let number: UInt32
    let header = NSView()
    let titleLabel = NSTextField(labelWithString: "")
    let toolLabel = NSTextField(labelWithString: "")
    let badge = NSTextField(labelWithString: "")
    let footer = NSTextField(labelWithString: "")
    let details = NSTextField(labelWithString: "Ayrıntılar ⌘I")
    let grip = NSView()
    var showsHeader = true
    var showsFooter = false
    var summaryOnly = false
    let summaryLabel = NSTextField(labelWithString: "")
    weak var canvas: CanvasView?
    private var dragStart: NSPoint?
    private var dragOrigin: NSPoint?

    init(number: UInt32) {
        self.number = number
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        header.wantsLayer = true
        addSubview(header)
        for label in [titleLabel, toolLabel, badge, footer, details, summaryLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.font = Theme.font()
        }
        titleLabel.font = Theme.font(bold: true)
        header.addSubview(titleLabel)
        header.addSubview(toolLabel)
        header.addSubview(badge)
        addSubview(footer)
        addSubview(details)
        addSubview(summaryLabel)
        grip.wantsLayer = true
        grip.layer?.cornerRadius = 4
        addSubview(grip)
        grip.toolTip = "Sürükleyerek Bağla"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func apply(info: SessionInfo, focused: Bool, model: AppModel) {
        let palette = Theme.palette
        titleLabel.stringValue = model.title(for: info)
        titleLabel.textColor = palette.fg
        toolLabel.stringValue = model.toolLabel(for: info)
        toolLabel.textColor = palette.dim
        layer?.backgroundColor = palette.bg.cgColor
        header.layer?.backgroundColor = palette.raise.cgColor
        let isAgent = info.tool != .terminal
        badge.isHidden = !isAgent
        badge.stringValue = "\(info.status.symbol) \(info.status.title)"
        var border = focused ? palette.fg : palette.line2
        switch info.status {
        case .needsApproval:
            badge.textColor = palette.need
            border = palette.need
        case .limitReached:
            badge.textColor = palette.limit
            border = palette.limit
        case .failed:
            badge.textColor = palette.err
            border = palette.err
        default:
            badge.textColor = info.status == .running ? palette.fg : palette.dim
        }
        layer?.borderColor = border.cgColor
        showsFooter = isAgent
        footer.isHidden = !isAgent
        details.isHidden = !isAgent
        footer.textColor = palette.dim
        details.textColor = palette.dim
        footer.stringValue = SessionText.footer(info)
        grip.isHidden = !canvasCanLink
        grip.layer?.backgroundColor = palette.line2.cgColor
        summaryLabel.stringValue = "\(info.status.symbol) \(model.title(for: info))"
        summaryLabel.textColor = palette.fg
        summaryLabel.isHidden = !summaryOnly
    }

    var canvasCanLink: Bool { canvas?.linkingEnabled ?? false }

    func layoutContents(host: NSView?, fontScale: CGFloat) {
        let width = bounds.width
        if summaryOnly {
            header.isHidden = true
            host?.isHidden = true
            summaryLabel.frame = bounds.insetBy(dx: 8, dy: (bounds.height - 20) / 2)
            footer.isHidden = true
            details.isHidden = true
            return
        }
        header.isHidden = !showsHeader
        host?.isHidden = false
        let headerHeight: CGFloat = showsHeader ? 32 : 0
        header.frame = NSRect(x: 0, y: 0, width: width, height: headerHeight)
        titleLabel.sizeToFit()
        badge.sizeToFit()
        toolLabel.sizeToFit()
        let badgeWidth = badge.isHidden ? 0 : badge.frame.width + 8
        let titleWidth = min(titleLabel.frame.width, max(40, width - 24 - badgeWidth - toolLabel.frame.width - 8))
        titleLabel.frame = NSRect(x: 12, y: 6, width: titleWidth, height: 20)
        toolLabel.frame.origin = NSPoint(x: titleLabel.frame.maxX + 8, y: 6)
        badge.frame.origin = NSPoint(x: width - badge.frame.width - 8, y: 6)
        let footerHeight: CGFloat = showsFooter ? 24 : 0
        if showsFooter {
            details.sizeToFit()
            details.frame.origin = NSPoint(x: width - details.frame.width - 12, y: bounds.height - 22)
            footer.frame = NSRect(x: 12, y: bounds.height - 22, width: max(0, details.frame.minX - 20), height: 20)
        }
        host?.frame = NSRect(x: 8, y: headerHeight + 4, width: width - 16, height: bounds.height - headerHeight - footerHeight - 8)
        grip.frame = NSRect(x: width - 9, y: bounds.height / 2 - 12, width: 8, height: 24)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if canvasCanLink, grip.frame.insetBy(dx: -6, dy: -6).contains(point) {
            canvas?.beginLink(from: self, event: event)
            return
        }
        AppModel.shared.setFocus(number)
        dragStart = event.locationInWindow
        dragOrigin = frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let dragOrigin, canvas?.allowsDrag == true else { return }
        let dx = event.locationInWindow.x - dragStart.x
        let dy = event.locationInWindow.y - dragStart.y
        canvas?.moveBox(self, to: NSPoint(x: dragOrigin.x + dx, y: dragOrigin.y - dy))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if showsFooter, details.frame.insetBy(dx: -4, dy: -4).contains(point) {
            AppModel.shared.setFocus(number)
            AppModel.shared.detailsOpen.toggle()
        }
        dragStart = nil
    }
}

enum SessionText {
    static func footer(_ info: SessionInfo) -> String {
        var parts: [String] = []
        if let account = info.accountID, let name = AccountStore.shared.account(id: account)?.name { parts.append(name) }
        if let model = info.model { parts.append(model) }
        if let effort = info.effort { parts.append(effort.capitalized) }
        if let tokens = info.contextTokens { parts.append(shortTokens(tokens) + " Token") }
        if parts.isEmpty { return info.status == .unknown ? "Durum Bilinmiyor" : info.tool.title }
        return parts.joined(separator: " · ")
    }

    static func shortTokens(_ value: Int) -> String {
        if value >= 1000 { return String(format: "%.1fk", Double(value) / 1000) }
        return "\(value)"
    }
}

/// The surface behind the boxes: dotted, pannable, zoomable. Only visible boxes hold terminals in view.
final class CanvasView: NSView {
    unowned let model: AppModel
    var boxes: [UInt32: SessionBox] = [:]
    var pan: CGPoint = .zero
    let linksLayer = CAShapeLayer()
    let linkPreview = CAShapeLayer()
    var linkingEnabled: Bool { model.mode == .canvas && model.maximized == nil && model.sessions.count > 1 }
    var allowsDrag: Bool { model.mode == .canvas && model.maximized == nil }
    var showsDots: Bool { false }
    private var linkSource: SessionBox?
    private var panStart: NSPoint?

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(linksLayer)
        layer?.addSublayer(linkPreview)
        linksLayer.fillColor = nil
        linkPreview.fillColor = nil
        linkPreview.lineDashPattern = [6, 4]
        linkPreview.lineWidth = 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let palette = Theme.palette
        palette.bg.setFill()
        dirtyRect.fill()
        guard model.mode == .canvas, model.maximized == nil, SettingsStore.shared.settings.canvasDots else { return }
        palette.line.setFill()
        let step: CGFloat = 24 * model.zoom
        var x = dirtyRect.minX - dirtyRect.minX.truncatingRemainder(dividingBy: step) + pan.x.truncatingRemainder(dividingBy: step)
        while x < dirtyRect.maxX {
            var y = dirtyRect.minY - dirtyRect.minY.truncatingRemainder(dividingBy: step) + pan.y.truncatingRemainder(dividingBy: step)
            while y < dirtyRect.maxY {
                NSRect(x: x, y: y, width: 1, height: 1).fill()
                y += step
            }
            x += step
        }
    }

    // MARK: Layout

    func relayout(animated: Bool) {
        let sessions = model.sessions
        let wanted = Set(sessions.map(\.number))
        for (number, box) in boxes where !wanted.contains(number) {
            box.removeFromSuperview()
            boxes[number] = nil
        }
        for info in sessions where boxes[info.number] == nil {
            let box = SessionBox(number: info.number)
            box.canvas = self
            boxes[info.number] = box
            addSubview(box)
        }
        let frames = computeFrames(sessions)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || PowerCenter.shared.settings.lowPower
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !reduceMotion ? 0.2 : 0
            for info in sessions {
                guard let box = boxes[info.number] else { continue }
                let target = frames[info.number]
                box.isHidden = target == nil
                if let target { (animated && !reduceMotion ? box.animator() : box).frame = target }
            }
        }
        applyContent()
        drawLinks()
        needsDisplay = true
    }

    func applyContent() {
        let single = model.sessions.count == 1 || model.maximized != nil || model.mode == .tabs
        let farAway = model.mode == .canvas && model.maximized == nil && model.zoom < 0.55
        for info in model.sessions {
            guard let box = boxes[info.number] else { continue }
            box.showsHeader = !single
            box.summaryOnly = farAway
            box.apply(info: info, focused: info.number == model.focused && !single, model: model)
            if single {
                box.layer?.borderWidth = 0
                box.layer?.cornerRadius = 0
            } else {
                box.layer?.borderWidth = 1
                box.layer?.cornerRadius = 6
            }
            if let host = model.hosts[info.number] {
                if box.isHidden || farAway {
                    if host.superview != nil { host.removeFromSuperview() }
                } else if host.superview !== box {
                    box.addSubview(host)
                }
                host.applyScaledFont(model.mode == .canvas && model.maximized == nil ? model.zoom : 1)
            }
            box.layoutContents(host: model.hosts[info.number], fontScale: model.zoom)
        }
    }

    func computeFrames(_ sessions: [SessionInfo]) -> [UInt32: NSRect] {
        var frames: [UInt32: NSRect] = [:]
        let area = bounds
        guard !sessions.isEmpty, area.width > 80, area.height > 80 else { return frames }
        if sessions.count == 1 || model.maximized != nil || model.mode == .tabs {
            let number = model.maximized ?? (model.mode == .tabs ? model.focused : sessions.first?.number) ?? sessions.first?.number
            if let number {
                frames[number] = NSRect(x: 8, y: 8, width: area.width - 16, height: area.height - 12)
            }
            return frames
        }
        let count = sessions.count
        if !model.state.freeLayout && count <= 6 {
            let columns = count <= 2 ? count : (count <= 4 ? 2 : 3)
            let rows = Int(ceil(Double(count) / Double(columns)))
            let gap: CGFloat = 16
            let width = (area.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
            let height = (area.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
            for (index, info) in sessions.enumerated() {
                let row = index / columns
                let column = index % columns
                let rect = NSRect(x: gap + CGFloat(column) * (width + gap), y: gap + CGFloat(row) * (height + gap), width: width, height: height)
                frames[info.number] = scaled(rect, around: area)
            }
            return frames
        }
        // Seven and more: boxes keep their size, the surface moves.
        let size = NSSize(width: 520, height: 320)
        for (index, info) in sessions.enumerated() {
            let saved = model.state.positions[info.id]
            let origin = saved ?? CGPoint(x: 16 + CGFloat(index % 3) * (size.width + 24), y: 16 + CGFloat(index / 3) * (size.height + 24))
            frames[info.number] = scaled(NSRect(origin: origin, size: size), around: area)
        }
        return frames
    }

    private func scaled(_ rect: NSRect, around area: NSRect) -> NSRect {
        let zoom = model.zoom
        return NSRect(x: rect.minX * zoom + pan.x, y: rect.minY * zoom + pan.y, width: rect.width * zoom, height: rect.height * zoom)
    }

    func fit() {
        pan = .zero
        model.state.freeLayout = false
        model.state.positions.removeAll()
        model.setZoom(1)
    }

    func moveBox(_ box: SessionBox, to origin: NSPoint) {
        guard let info = model.sessions.first(where: { $0.number == box.number }) else { return }
        if !model.state.freeLayout {
            // The first drag freezes the tile layout into free positions.
            let zoom = model.zoom
            for session in model.sessions {
                if let other = boxes[session.number] {
                    model.state.positions[session.id] = CGPoint(x: (other.frame.minX - pan.x) / zoom, y: (other.frame.minY - pan.y) / zoom)
                }
            }
            model.state.freeLayout = true
        }
        box.frame.origin = origin
        model.state.positions[info.id] = CGPoint(x: (origin.x - pan.x) / model.zoom, y: (origin.y - pan.y) / model.zoom)
        drawLinks()
    }

    override func layout() {
        super.layout()
        relayout(animated: false)
    }

    // MARK: Empty surface

    override func mouseDown(with event: NSEvent) { panStart = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = panStart, allowsDrag else { return }
        pan.x += event.locationInWindow.x - start.x
        pan.y -= event.locationInWindow.y - start.y
        panStart = event.locationInWindow
        relayout(animated: false)
    }

    override func scrollWheel(with event: NSEvent) {
        guard allowsDrag else { return }
        pan.x += event.scrollingDeltaX
        pan.y += event.scrollingDeltaY
        relayout(animated: false)
    }

    // MARK: Links

    func beginLink(from box: SessionBox, event: NSEvent) {
        linkSource = box
        trackLink(event)
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { [weak self] tracked, stop in
            guard let self, let tracked else { return }
            if tracked.type == .leftMouseUp {
                self.finishLink(tracked)
                stop.pointee = true
            } else {
                self.trackLink(tracked)
            }
        }
    }

    private func trackLink(_ event: NSEvent) {
        guard let source = linkSource else { return }
        let point = convert(event.locationInWindow, from: nil)
        let path = CGMutablePath()
        path.move(to: NSPoint(x: source.frame.maxX, y: source.frame.midY))
        path.addLine(to: point)
        linkPreview.strokeColor = Theme.palette.fg.cgColor
        linkPreview.path = path
        for box in boxes.values where box !== source {
            box.layer?.borderColor = box.frame.contains(point) ? Theme.palette.need.cgColor : Theme.palette.line2.cgColor
        }
    }

    private func finishLink(_ event: NSEvent) {
        linkPreview.path = nil
        guard let source = linkSource else { return }
        linkSource = nil
        let point = convert(event.locationInWindow, from: nil)
        if let target = boxes.values.first(where: { $0 !== source && $0.frame.contains(point) && !$0.isHidden }) {
            model.overlay = .linkPermission(from: source.number, to: target.number)
        }
        applyContent()
    }

    func drawLinks() {
        let palette = Theme.palette
        linksLayer.frame = bounds
        linkPreview.frame = bounds
        linksLayer.strokeColor = palette.dim.cgColor
        linksLayer.lineWidth = 1.5
        let path = CGMutablePath()
        if model.mode == .canvas, model.maximized == nil {
            for link in LinkStore.shared.links {
                guard let from = model.sessions.first(where: { $0.id == link.from }), let to = model.sessions.first(where: { $0.id == link.to }),
                      let a = boxes[from.number], let b = boxes[to.number] else { continue }
                let start = NSPoint(x: a.frame.maxX, y: a.frame.midY)
                let end = NSPoint(x: b.frame.minX, y: b.frame.midY)
                path.move(to: start)
                let bend = max(40, abs(end.x - start.x) / 2)
                path.addCurve(to: end, control1: NSPoint(x: start.x + bend, y: start.y), control2: NSPoint(x: end.x - bend, y: end.y))
            }
        }
        linksLayer.path = path
        linksLayer.zPosition = 10
    }
}
