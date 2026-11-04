import AppKit
import EntermCore

/// Drawn only: the box under it handles the mouse.
class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private func symbolImage(_ name: String, size: CGFloat) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size * 0.85, weight: .regular))
}

/// The status chip on a box: symbol and word on a soft ground, no frame.
final class BadgeView: PassThroughView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Theme.cornerControl
        addSubview(icon)
        addSubview(label)
        label.lineBreakMode = .byClipping
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func apply(_ status: SessionStatus) {
        let look = StatusLook(status)
        icon.image = symbolImage(look.symbol, size: 8)
        icon.contentTintColor = look.symbolColor
        label.stringValue = status.title
        label.font = Theme.ui(.secondary, weight: look.strong ? .semibold : .medium)
        label.textColor = look.textColor
        layer?.backgroundColor = look.background.cgColor
        label.sizeToFit()
        let width = 6 + 8 + 6 + label.frame.width + 8
        frame.size = NSSize(width: ceil(width), height: 20)
        icon.frame = NSRect(x: 6, y: 6, width: 8, height: 8)
        label.frame.origin = NSPoint(x: 20, y: (20 - label.frame.height) / 2)
    }
}

/// One session on the canvas: a header, the live terminal, and for agents a one line footer.
final class SessionBox: NSView {
    let number: UInt32
    let header = PassThroughView()
    let programIcon = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let folderLabel = NSTextField(labelWithString: "")
    let badge = BadgeView()
    let footerBar = PassThroughView()
    let footer = NSTextField(labelWithString: "")
    let details = NSTextField(labelWithString: "Ayrıntılar")
    let detailsKey = NSTextField(labelWithString: "⌘I")
    let grip = PassThroughView()
    let gripIcon = NSImageView()
    var showsHeader = true
    var showsFooter = false
    var summaryOnly = false
    let summaryLabel = NSTextField(labelWithString: "")
    weak var canvas: CanvasView?
    private var dragStart: NSPoint?
    private var dragOrigin: NSPoint?
    private var linking = false
    private var isAgent = false
    private var shadowSize = NSSize.zero

    init(number: UInt32) {
        self.number = number
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.cornerCard
        layer?.borderWidth = 1
        header.wantsLayer = true
        header.layer?.cornerRadius = Theme.cornerCard
        header.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        addSubview(header)
        footerBar.wantsLayer = true
        footerBar.layer?.cornerRadius = Theme.cornerCard
        footerBar.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(footerBar)
        for label in [titleLabel, folderLabel, footer, details, detailsKey, summaryLabel] {
            label.lineBreakMode = .byTruncatingTail
        }
        folderLabel.lineBreakMode = .byTruncatingHead
        titleLabel.font = Theme.ui(.body, weight: .semibold)
        folderLabel.font = Theme.ui(.secondary)
        footer.font = Theme.ui(.secondary)
        details.font = Theme.ui(.secondary)
        detailsKey.font = Theme.ui(.hint)
        summaryLabel.font = Theme.ui(.body, weight: .semibold)
        header.addSubview(programIcon)
        header.addSubview(titleLabel)
        header.addSubview(folderLabel)
        header.addSubview(badge)
        footerBar.addSubview(footer)
        footerBar.addSubview(details)
        footerBar.addSubview(detailsKey)
        addSubview(summaryLabel)
        grip.wantsLayer = true
        grip.layer?.cornerRadius = Theme.cornerControl
        gripIcon.image = symbolImage("link", size: 14)
        gripIcon.frame = NSRect(x: 5, y: 5, width: 14, height: 14)
        grip.addSubview(gripIcon)
        addSubview(grip)
        grip.toolTip = "Sürükleyerek Bağla"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func apply(info: SessionInfo, focused: Bool, model: AppModel) {
        let palette = Theme.palette
        isAgent = info.tool != .terminal
        let attention = info.status == .needsApproval || info.status == .limitReached || info.status == .failed
        titleLabel.stringValue = model.name(for: info)
        titleLabel.textColor = focused || attention ? palette.text1 : palette.text2
        folderLabel.stringValue = model.displayPath(info.cwd)
        folderLabel.textColor = focused ? palette.text2 : palette.text3
        programIcon.image = symbolImage(isAgent ? "sparkle" : "terminal", size: 14)
        programIcon.contentTintColor = focused ? palette.text2 : palette.text3
        layer?.backgroundColor = palette.terminal.cgColor
        header.layer?.backgroundColor = (focused ? palette.surface2 : palette.surface1).cgColor
        footerBar.layer?.backgroundColor = palette.surface1.cgColor
        badge.isHidden = !isAgent
        if isAgent { badge.apply(info.status) }
        var border = focused ? palette.focus : palette.hair2
        var borderWidth: CGFloat = 1
        switch info.status {
        case .needsApproval:
            border = palette.need
            borderWidth = 2
        case .limitReached:
            border = palette.limit
            borderWidth = 2
        case .failed:
            border = palette.err
            borderWidth = 2
        default:
            break
        }
        layer?.borderColor = border.cgColor
        layer?.borderWidth = borderWidth
        applyShadow(focused || info.status == .needsApproval)
        showsFooter = isAgent
        footerBar.isHidden = !isAgent
        footer.textColor = palette.text2
        details.textColor = palette.text2
        detailsKey.textColor = palette.text3
        footer.stringValue = SessionText.footer(info)
        gripIcon.contentTintColor = palette.text2
        updateGrip()
        summaryLabel.stringValue = "\(info.status.symbol) \(model.name(for: info))"
        summaryLabel.textColor = palette.text1
        summaryLabel.isHidden = !summaryOnly
    }

    /// Only the focused box casts a shadow, and its outline is computed once per size.
    private func applyShadow(_ on: Bool) {
        guard let layer else { return }
        layer.shadowColor = Theme.palette.shadowBox.cgColor
        layer.shadowOpacity = on ? 1 : 0
        layer.shadowRadius = on ? 8 : 0
        layer.shadowOffset = on ? CGSize(width: 0, height: -4) : .zero
        if !on { layer.shadowPath = nil; shadowSize = .zero }
        if on, shadowSize != bounds.size {
            shadowSize = bounds.size
            layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Theme.cornerCard, cornerHeight: Theme.cornerCard, transform: nil)
        }
    }

    var canvasCanLink: Bool { canvas?.linkingEnabled ?? false }

    /// The grip lives in the header and shows under the mouse, so nothing sits on the terminal.
    private var hovering = false
    private var overGrip = false

    private func updateGrip() {
        grip.isHidden = !(canvasCanLink && showsHeader && (hovering || linking))
        grip.layer?.backgroundColor = overGrip ? Theme.palette.fill.cgColor : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateGrip()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        overGrip = false
        updateGrip()
    }

    override func mouseMoved(with event: NSEvent) {
        let over = grip.frame.contains(convert(event.locationInWindow, from: nil))
        guard over != overGrip else { return }
        overGrip = over
        updateGrip()
    }

    func layoutContents(host: NSView?, fontScale: CGFloat) {
        let width = bounds.width
        if summaryOnly {
            header.isHidden = true
            footerBar.isHidden = true
            host?.isHidden = true
            grip.isHidden = true
            summaryLabel.frame = bounds.insetBy(dx: 8, dy: (bounds.height - 20) / 2)
            return
        }
        header.isHidden = !showsHeader
        host?.isHidden = false
        let headerHeight: CGFloat = showsHeader ? 32 : 0
        header.frame = NSRect(x: 0, y: 0, width: width, height: headerHeight)
        programIcon.frame = NSRect(x: 10, y: 9, width: 14, height: 14)
        let badgeWidth = badge.isHidden ? 0 : badge.frame.width
        let right = badge.isHidden ? width - 6 : width - 6 - badgeWidth
        badge.frame.origin = NSPoint(x: right, y: 6)
        grip.frame = NSRect(x: (badge.isHidden ? right : right - 6) - 24, y: 4, width: 24, height: 24)
        titleLabel.sizeToFit()
        folderLabel.sizeToFit()
        // The folder gives way first, then the name.
        let textStart: CGFloat = 30
        let textEnd = grip.frame.minX - 8
        let room = max(0, textEnd - textStart)
        let titleWidth = min(titleLabel.frame.width, room)
        titleLabel.frame = NSRect(x: textStart, y: 7, width: titleWidth, height: 18)
        let folderX = titleLabel.frame.maxX + 8
        folderLabel.frame = NSRect(x: folderX, y: 8, width: max(0, min(folderLabel.frame.width, textEnd - folderX)), height: 16)
        let footerHeight: CGFloat = showsFooter ? 24 : 0
        footerBar.frame = NSRect(x: 0, y: bounds.height - footerHeight, width: width, height: footerHeight)
        if showsFooter {
            detailsKey.sizeToFit()
            details.sizeToFit()
            detailsKey.frame.origin = NSPoint(x: width - detailsKey.frame.width - 12, y: (24 - detailsKey.frame.height) / 2)
            details.frame.origin = NSPoint(x: detailsKey.frame.minX - details.frame.width - 6, y: (24 - details.frame.height) / 2)
            footer.frame = NSRect(x: 12, y: (24 - 16) / 2, width: max(0, details.frame.minX - 20), height: 16)
        }
        // Rows and columns do not depend on how many sessions are open.
        host?.frame = NSRect(x: 8, y: headerHeight + 4, width: width - 16, height: bounds.height - headerHeight - footerHeight - 8)
        addSubview(grip, positioned: .above, relativeTo: nil)
        if layer?.shadowOpacity ?? 0 > 0, shadowSize != bounds.size {
            shadowSize = bounds.size
            layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Theme.cornerCard, cornerHeight: Theme.cornerCard, transform: nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if canvasCanLink, !grip.isHidden, grip.frame.contains(point) {
            linking = true
            canvas?.beginLink(from: self, event: event)
            return
        }
        AppModel.shared.setFocus(number)
        dragStart = event.locationInWindow
        dragOrigin = frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        if linking {
            canvas?.continueLink(event)
            return
        }
        guard let dragStart, let dragOrigin, canvas?.allowsDrag == true else { return }
        let dx = event.locationInWindow.x - dragStart.x
        let dy = event.locationInWindow.y - dragStart.y
        canvas?.moveBox(self, to: NSPoint(x: dragOrigin.x + dx, y: dragOrigin.y - dy))
    }

    override func mouseUp(with event: NSEvent) {
        if linking {
            linking = false
            canvas?.endLink(event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if showsFooter, footerBar.convert(details.frame, to: self).insetBy(dx: -4, dy: -4).contains(point) {
            AppModel.shared.setFocus(number)
            AppModel.shared.detailsOpen.toggle()
        }
        dragStart = nil
    }
}

enum SessionText {
    static func footer(_ info: SessionInfo) -> String {
        if info.status == .notFound {
            if case .elsewhere(let path)? = ToolCatalog.shared.presence[info.tool] { return "Bulundu: \(path)" }
            if let command = ToolPresence.installCommand(info.tool) { return "Kurulum: \(command)" }
        }
        var parts: [String] = []
        if let account = info.accountID, let name = AccountStore.shared.account(id: account)?.name { parts.append(name) }
        if let model = info.model { parts.append(model) }
        if let effort = info.effort { parts.append(effortTitle(effort)) }
        if let tokens = info.contextTokens { parts.append(shortTokens(tokens) + " Token") }
        if parts.isEmpty { return info.status == .unknown ? "Durum Bilinmiyor" : info.tool.title }
        return parts.joined(separator: " · ")
    }

    static func effortTitle(_ effort: String) -> String {
        switch effort {
        case "low": return "Düşük"
        case "medium": return "Orta"
        case "high": return "Yüksek"
        case "xhigh", "max": return "En Fazla"
        default: return effort
        }
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
        palette.surface0.setFill()
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

    override func mouseDown(with event: NSEvent) {
        if let link = link(at: convert(event.locationInWindow, from: nil)) {
            model.overlay = .linkDetail(link.id)
            return
        }
        panStart = event.locationInWindow
    }

    /// A click near a line opens its details. Curves are close enough to their chord for this.
    private func link(at point: NSPoint) -> SessionLink? {
        guard allowsDrag else { return nil }
        for link in LinkStore.shared.links {
            guard let from = model.sessions.first(where: { $0.id == link.from }), let to = model.sessions.first(where: { $0.id == link.to }),
                  let a = boxes[from.number], let b = boxes[to.number] else { continue }
            let start = NSPoint(x: a.frame.maxX, y: a.frame.midY)
            let end = NSPoint(x: b.frame.minX, y: b.frame.midY)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 1 else { continue }
            let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
            if hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy)) < 24 { return link }
        }
        return nil
    }

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
    }

    func continueLink(_ event: NSEvent) { trackLink(event) }

    func endLink(_ event: NSEvent) { finishLink(event) }

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
