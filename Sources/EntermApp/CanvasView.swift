import AppKit
import EntermCore
import SwiftUI

/// Drawn only: the box under it handles the mouse.
class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private func symbolImage(_ name: String, size: CGFloat) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size * 0.85, weight: .regular))
}

/// The status chip on a box: symbol and word on a soft ground, no frame.
final class BadgeView: PassThroughView {
    let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Theme.cornerControl
        icon.wantsLayer = true
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
        layer?.backgroundColor = look.strong ? look.background.cgColor : nil
        label.sizeToFit()
        let width = 6 + 8 + 6 + label.frame.width + 8
        frame.size = NSSize(width: ceil(width), height: 20)
        icon.frame = NSRect(x: 6, y: 6, width: 8, height: 8)
        label.frame.origin = NSPoint(x: 20, y: (20 - label.frame.height) / 2)
    }
}

/// One session on the canvas: a name tab, the live terminal, and the state on the line beside the tab.
/// Two opposite corners carry a light in the colour of the state.
final class SessionBox: NSView {
    let number: UInt32
    let panel = PassThroughView()
    let header = PassThroughView()
    let programIcon = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let folderLabel = NSTextField(labelWithString: "")
    let badge = BadgeView()
    let stripLabel = NSTextField(labelWithString: "")
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
    private let tickStart = CAShapeLayer()
    private let tickEnd = CAShapeLayer()
    private let sweep = CAGradientLayer()
    private var tickSize = NSSize.zero
    private var lastStatus: SessionStatus?
    private(set) var isRunning = false
    private let closeButton = NSButton()
    private let maximizeButton = NSButton()
    private var chatHost: NSHostingView<ChatView>?
    private var approvalHost: NSHostingView<ApprovalBar>?
    private var pendingApproval: ApprovalRequest?
    private enum ResizeEdge { case right, bottom, corner }
    private var resizing: ResizeEdge?
    private var resizeStart: NSRect?
    private var dragged = false

    init(number: UInt32) {
        self.number = number
        super.init(frame: .zero)
        wantsLayer = true
        panel.wantsLayer = true
        panel.layer?.borderWidth = 1
        addSubview(panel)
        header.wantsLayer = true
        header.layer?.cornerRadius = Theme.cornerCard
        header.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        addSubview(header)
        footerBar.wantsLayer = true
        footerBar.layer?.cornerRadius = Theme.cornerCard
        footerBar.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(footerBar)
        for label in [titleLabel, folderLabel, footer, details, detailsKey, summaryLabel, stripLabel] {
            label.lineBreakMode = .byTruncatingTail
        }
        folderLabel.lineBreakMode = .byTruncatingHead
        titleLabel.font = Theme.ui(.body, weight: .semibold)
        folderLabel.font = Theme.ui(.secondary)
        stripLabel.font = Theme.ui(.secondary)
        stripLabel.alignment = .right
        footer.font = Theme.ui(.secondary)
        details.font = Theme.ui(.secondary)
        detailsKey.font = Theme.ui(.hint)
        summaryLabel.font = Theme.ui(.body, weight: .semibold)
        header.addSubview(programIcon)
        header.addSubview(titleLabel)
        header.addSubview(folderLabel)
        addSubview(badge)
        addSubview(stripLabel)
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
        for (button, symbol, tip) in [(closeButton, "xmark", "Kapat (⌘W)"), (maximizeButton, "arrow.up.left.and.arrow.down.right", "Tam Ekran (⌘⏎)")] {
            button.image = symbolImage(symbol, size: 12)
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.toolTip = tip
            button.target = self
            button.isHidden = true
            addSubview(button)
        }
        closeButton.action = #selector(closeTapped)
        maximizeButton.action = #selector(maximizeTapped)
        for tick in [tickStart, tickEnd] {
            tick.fillColor = nil
            tick.lineWidth = 2
            tick.lineCap = .round
            tick.shadowOffset = .zero
            tick.isHidden = true
            panel.layer?.addSublayer(tick)
        }
        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        sweep.anchorPoint = CGPoint(x: 0, y: 0.5)
        sweep.isHidden = true
        panel.layer?.addSublayer(sweep)
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
        programIcon.contentTintColor = Neon.color(info) ?? (focused ? palette.text2 : palette.text3)
        panel.layer?.backgroundColor = TerminalTheme.current.backgroundColor.cgColor
        header.layer?.backgroundColor = (focused ? palette.surface2 : palette.surface1).cgColor
        footerBar.layer?.backgroundColor = palette.surface1.cgColor
        badge.isHidden = !isAgent || !showsHeader
        if isAgent { badge.apply(info.status) }
        let light = Neon.color(info)
        var border = focused ? palette.focus : palette.hair2
        if attention, let light { border = light.withAlphaComponent(0.55) }
        panel.layer?.borderColor = border.cgColor
        panel.layer?.borderWidth = 1
        applyShadow(focused || info.status == .needsApproval)
        applyLight(light, attention: attention)
        if MotionPolicy.sweeps(from: lastStatus, to: info.status), Motion.allowed, Neon.on { runSweep() }
        if info.status == .running, lastStatus != .running { canvas?.flowLinks(of: info.id) }
        lastStatus = info.status
        pendingApproval = info.pendingApproval
        isRunning = info.status == .running
        if !isRunning { badge.icon.layer?.opacity = 1 }
        showsFooter = isAgent && !showsHeader
        footerBar.isHidden = !showsFooter
        footer.textColor = palette.text2
        details.textColor = palette.text2
        detailsKey.textColor = palette.text3
        footer.stringValue = SessionText.footer(info)
        let line = SessionText.footer(info)
        stripLabel.stringValue = isAgent && line != info.tool.title ? line : ""
        stripLabel.textColor = palette.text3
        stripLabel.isHidden = !isAgent || !showsHeader
        gripIcon.contentTintColor = palette.text2
        updateGrip()
        summaryLabel.stringValue = "\(info.status.symbol) \(model.name(for: info))"
        summaryLabel.textColor = palette.text1
        summaryLabel.isHidden = !summaryOnly
    }

    /// Drawn once and left alone: a light that does not move costs nothing to keep.
    private func applyLight(_ color: NSColor?, attention: Bool) {
        let visible = color != nil && Neon.on && showsHeader && !summaryOnly
        for tick in [tickStart, tickEnd] {
            tick.isHidden = !visible
            guard visible, let color else { continue }
            tick.strokeColor = color.cgColor
            tick.opacity = Neon.opacity
            tick.shadowColor = color.cgColor
            tick.shadowOpacity = 0.9
            tick.shadowRadius = Neon.radius
        }
        sweep.isHidden = !(visible && attention)
        if visible, let color {
            sweep.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
            sweep.opacity = 0.35 * Neon.opacity
        }
    }

    private func runSweep() {
        let grow = CABasicAnimation(keyPath: "transform.scale.x")
        grow.fromValue = 0
        grow.toValue = 1
        grow.duration = 0.7
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.2, 1)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Neon.opacity
        fade.toValue = 0.35 * Neon.opacity
        fade.beginTime = 0.5
        fade.duration = 0.5
        fade.fillMode = .backwards
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 1
        sweep.add(group, forKey: "sweep")
    }

    private func placeLight() {
        let size = panel.bounds.size
        guard size != tickSize, size.width > 0 else { return }
        tickSize = size
        let length: CGFloat = 20, radius = Theme.cornerCard
        let start = CGMutablePath()
        start.move(to: CGPoint(x: 0, y: size.height - length))
        start.addLine(to: CGPoint(x: 0, y: size.height))
        start.addLine(to: CGPoint(x: length, y: size.height))
        let end = CGMutablePath()
        end.move(to: CGPoint(x: size.width - length, y: 0))
        end.addLine(to: CGPoint(x: size.width - radius, y: 0))
        end.addQuadCurve(to: CGPoint(x: size.width, y: radius), control: CGPoint(x: size.width, y: 0))
        end.addLine(to: CGPoint(x: size.width, y: length))
        tickStart.path = start
        tickEnd.path = end
        // A given outline: the shadow is computed once per size, never per frame.
        tickStart.shadowPath = start.copy(strokingWithWidth: 2, lineCap: .round, lineJoin: .miter, miterLimit: 4)
        tickEnd.shadowPath = end.copy(strokingWithWidth: 2, lineCap: .round, lineJoin: .miter, miterLimit: 4)
        sweep.frame = CGRect(x: 0, y: size.height - 1, width: size.width, height: 2)
    }

    /// Only the focused box casts a shadow, and its outline is computed once per size.
    private func applyShadow(_ on: Bool) {
        guard let layer = panel.layer else { return }
        layer.shadowColor = Theme.palette.shadowBox.cgColor
        layer.shadowOpacity = on ? 1 : 0
        layer.shadowRadius = on ? 8 : 0
        layer.shadowOffset = on ? CGSize(width: 0, height: -4) : .zero
        if !on { layer.shadowPath = nil; shadowSize = .zero }
        if on, shadowSize != panel.bounds.size {
            shadowSize = panel.bounds.size
            layer.shadowPath = CGPath(roundedRect: panel.bounds, cornerWidth: Theme.cornerCard, cornerHeight: Theme.cornerCard, transform: nil)
        }
    }

    var canvasCanLink: Bool { canvas?.linkingEnabled ?? false }

    /// The grip lives in the header and shows under the mouse, so nothing sits on the terminal.
    private var hovering = false
    private var overGrip = false

    private func updateGrip() {
        grip.isHidden = !(canvasCanLink && showsHeader && (hovering || linking))
        grip.layer?.backgroundColor = overGrip ? Theme.palette.fill.cgColor : nil
        let controls = !showsHeader || summaryOnly || !hovering
        closeButton.isHidden = controls
        maximizeButton.isHidden = controls
        closeButton.contentTintColor = Theme.palette.text2
        maximizeButton.contentTintColor = Theme.palette.text2
    }

    @objc private func closeTapped() {
        guard let info = AppModel.shared.sessions.first(where: { $0.number == number }) else { return }
        let model = AppModel.shared
        // A program that is working is not closed by a stray click.
        if info.tool != .terminal, info.status == .running {
            model.confirm(title: "\(model.name(for: info)) Kapatılsın mı?", detail: "Çalışan program da kapanır. Konuşma programın kendi geçmişinde kalır.", action: "Kapat") { model.close(number) }
        } else {
            model.close(number)
        }
    }

    @objc private func maximizeTapped() {
        AppModel.shared.setFocus(number)
        AppModel.shared.toggleMaximize()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateGrip()
        layoutContents(host: AppModel.shared.hosts[number], fontScale: AppModel.shared.zoom)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        overGrip = false
        updateGrip()
        layoutContents(host: AppModel.shared.hosts[number], fontScale: AppModel.shared.zoom)
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
            badge.isHidden = true
            stripLabel.isHidden = true
            host?.isHidden = true
            grip.isHidden = true
            panel.frame = bounds
            summaryLabel.frame = bounds.insetBy(dx: 8, dy: (bounds.height - 20) / 2)
            return
        }
        header.isHidden = !showsHeader
        host?.isHidden = false
        let tabHeight: CGFloat = showsHeader ? 30 : 0
        // The tab holds the name and gives way before the line beside it does.
        let badgeWidth = badge.isHidden ? 0 : badge.frame.width
        badge.frame.origin = NSPoint(x: width - badgeWidth, y: 5)
        titleLabel.sizeToFit()
        folderLabel.sizeToFit()
        let textStart: CGFloat = 30
        let tabLimit = max(120, width * 0.62)
        let titleWidth = min(titleLabel.frame.width, tabLimit - textStart - 12)
        let folderRoom = tabLimit - textStart - titleWidth - 20
        let folderWidth = folderRoom > 40 ? min(folderLabel.frame.width, folderRoom) : 0
        let tabWidth = ceil(textStart + titleWidth + (folderWidth > 0 ? 8 + folderWidth : 0) + 12)
        header.frame = NSRect(x: 0, y: 0, width: tabWidth, height: max(tabHeight, 0))
        programIcon.frame = NSRect(x: 10, y: 8, width: 14, height: 14)
        titleLabel.frame = NSRect(x: textStart, y: 6, width: titleWidth, height: 18)
        folderLabel.isHidden = folderWidth == 0
        folderLabel.frame = NSRect(x: titleLabel.frame.maxX + 8, y: 7, width: folderWidth, height: 16)
        // On hover the controls take the end of the line, the state moves in beside them.
        let hoverRoom: CGFloat = hovering ? 52 : 0
        closeButton.frame = NSRect(x: width - 24, y: 4, width: 22, height: 22)
        maximizeButton.frame = NSRect(x: width - 48, y: 4, width: 22, height: 22)
        badge.frame.origin = NSPoint(x: width - badgeWidth - hoverRoom, y: 5)
        let lineEnd = badge.isHidden ? width - hoverRoom : badge.frame.minX - 8
        grip.frame = NSRect(x: max(tabWidth + 4, lineEnd - 24), y: 3, width: 24, height: 24)
        let labelEnd = grip.isHidden ? lineEnd : grip.frame.minX - 4
        stripLabel.frame = NSRect(x: tabWidth + 8, y: 7, width: max(0, labelEnd - tabWidth - 8), height: 16)
        panel.frame = NSRect(x: 0, y: max(0, tabHeight - 1), width: width, height: bounds.height - max(0, tabHeight - 1))
        panel.layer?.cornerRadius = showsHeader ? Theme.cornerCard : 0
        panel.layer?.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMinYCorner, .layerMaxXMinYCorner]
        placeLight()
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
        let content = NSRect(x: 8, y: tabHeight + 4, width: width - 16, height: bounds.height - tabHeight - footerHeight - 8)
        host?.frame = content
        if AppModel.shared.chatSessions.contains(number) {
            if chatHost == nil {
                let view = NSHostingView(rootView: ChatView(number: number))
                view.safeAreaRegions = []
                addSubview(view)
                chatHost = view
            }
            chatHost?.frame = NSRect(x: 1, y: tabHeight, width: width - 2, height: bounds.height - tabHeight - footerHeight - 1)
            host?.isHidden = true
        } else if let view = chatHost {
            view.removeFromSuperview()
            chatHost = nil
        }
        // A question stays inside its own box and never takes the keyboard from another one.
        if let request = pendingApproval, !AppModel.shared.chatSessions.contains(number) {
            let bar = ApprovalBar(request: request, number: number)
            if let view = approvalHost {
                view.rootView = bar
            } else {
                let view = NSHostingView(rootView: bar)
                view.safeAreaRegions = []
                addSubview(view)
                approvalHost = view
            }
            let height: CGFloat = 92
            approvalHost?.frame = NSRect(x: 1, y: bounds.height - footerHeight - height - 1, width: width - 2, height: height)
            addSubview(approvalHost!, positioned: .above, relativeTo: nil)
        } else if let view = approvalHost {
            view.removeFromSuperview()
            approvalHost = nil
        }
        addSubview(grip, positioned: .above, relativeTo: nil)
        addSubview(closeButton, positioned: .above, relativeTo: nil)
        addSubview(maximizeButton, positioned: .above, relativeTo: nil)
        window?.invalidateCursorRects(for: self)
        if panel.layer?.shadowOpacity ?? 0 > 0, shadowSize != panel.bounds.size {
            shadowSize = panel.bounds.size
            panel.layer?.shadowPath = CGPath(roundedRect: panel.bounds, cornerWidth: Theme.cornerCard, cornerHeight: Theme.cornerCard, transform: nil)
        }
    }

    private func edge(at point: NSPoint) -> ResizeEdge? {
        guard showsHeader, !summaryOnly, canvas?.allowsDrag == true else { return nil }
        let right = point.x > bounds.width - 8, bottom = point.y > bounds.height - 8
        if right && bottom { return .corner }
        if right && point.y > 30 { return .right }
        if bottom { return .bottom }
        return nil
    }

    override func resetCursorRects() {
        guard showsHeader, !summaryOnly, canvas?.allowsDrag == true else { return }
        addCursorRect(NSRect(x: bounds.width - 8, y: 30, width: 8, height: bounds.height - 30), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 0, y: bounds.height - 8, width: bounds.width, height: 8), cursor: .resizeUpDown)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let info = AppModel.shared.sessions.first(where: { $0.number == number }) else { return nil }
        return CanvasMenus.session(info)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if canvasCanLink, !grip.isHidden, grip.frame.contains(point) {
            linking = true
            canvas?.beginLink(from: self, event: event)
            return
        }
        AppModel.shared.setFocus(number)
        dragged = false
        dragStart = event.locationInWindow
        dragOrigin = frame.origin
        if let edge = edge(at: point) {
            resizing = edge
            resizeStart = frame
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if linking {
            canvas?.continueLink(event)
            return
        }
        guard let dragStart, let dragOrigin, canvas?.allowsDrag == true else { return }
        if !dragged {
            dragged = true
            AppModel.shared.pushLayoutUndo()
        }
        let dx = event.locationInWindow.x - dragStart.x
        let dy = event.locationInWindow.y - dragStart.y
        if let resizing, let resizeStart {
            var size = resizeStart.size
            if resizing != .bottom { size.width += dx }
            if resizing != .right { size.height -= dy }
            canvas?.resizeBox(self, to: size)
            return
        }
        canvas?.moveBox(self, to: NSPoint(x: dragOrigin.x + dx, y: dragOrigin.y - dy))
    }

    override func mouseUp(with event: NSEvent) {
        if linking {
            linking = false
            canvas?.endLink(event)
            return
        }
        resizing = nil
        resizeStart = nil
        let point = convert(event.locationInWindow, from: nil)
        let onDetails = showsFooter && footerBar.convert(details.frame, to: self).insetBy(dx: -4, dy: -4).contains(point)
        let onState = showsHeader && isAgent && (stripLabel.frame.contains(point) || badge.frame.contains(point))
        if onDetails || onState, let start = dragStart, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) < 4 {
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
        if let model = info.model { parts.append(ModelName.pretty(model)) }
        if let effort = info.effort { parts.append(effortTitle(effort)) }
        if let percent = info.contextPercent {
            parts.append("%\(percent) Bağlam")
        } else if let tokens = info.contextTokens {
            parts.append(shortTokens(tokens) + " Token")
        }
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

/// Where everything on the surface is, in outlines. It draws only when the layout changes.
final class MiniMapView: NSView {
    weak var canvas: CanvasView?
    override var isFlipped: Bool { true }

    private var world: NSRect {
        guard let canvas else { return .zero }
        return canvas.boxes.values.reduce(canvas.bounds) { $0.union($1.frame) }.insetBy(dx: -24, dy: -24)
    }

    private func scale(_ world: NSRect) -> CGFloat { min(bounds.width / max(world.width, 1), bounds.height / max(world.height, 1)) }

    override func draw(_ dirtyRect: NSRect) {
        guard let canvas else { return }
        let palette = Theme.palette
        palette.surface1.setFill()
        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Theme.cornerCard, yRadius: Theme.cornerCard)
        frame.fill()
        palette.hair2.setStroke()
        frame.stroke()
        let world = self.world, factor = scale(world)
        func map(_ rect: NSRect) -> NSRect {
            NSRect(x: (rect.minX - world.minX) * factor, y: (rect.minY - world.minY) * factor, width: rect.width * factor, height: rect.height * factor)
        }
        for info in canvas.model.sessions {
            guard let box = canvas.boxes[info.number], !box.isHidden else { continue }
            (Neon.color(info) ?? palette.hair2).setStroke()
            let path = NSBezierPath(roundedRect: map(box.frame).insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
            path.lineWidth = 1.5
            path.stroke()
        }
        palette.focus.setStroke()
        NSBezierPath(rect: map(canvas.bounds).insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func mouseDown(with event: NSEvent) { recenter(event) }
    override func mouseDragged(with event: NSEvent) { recenter(event) }

    private func recenter(_ event: NSEvent) {
        guard let canvas else { return }
        let point = convert(event.locationInWindow, from: nil)
        let world = self.world, factor = scale(world)
        guard factor > 0 else { return }
        let target = NSPoint(x: world.minX + point.x / factor, y: world.minY + point.y / factor)
        canvas.pan.x += canvas.bounds.midX - target.x
        canvas.pan.y += canvas.bounds.midY - target.y
        canvas.relayout(animated: false)
    }
}

/// The surface behind the boxes: a faint grid, pannable, zoomable. Only visible boxes hold terminals in view.
final class CanvasView: NSView {
    unowned let model: AppModel
    var boxes: [UInt32: SessionBox] = [:]
    var pan: CGPoint = .zero
    let linksLayer = CAShapeLayer()
    let linkPreview = CAShapeLayer()
    private let glowTop = CAGradientLayer()
    private let glowBottom = CAGradientLayer()
    private let miniMap = MiniMapView()
    private var linkRoutes: [(link: SessionLink, route: [CGPoint])] = []
    private var linkLabels: [CATextLayer] = []
    private var pulseTimer: Timer?
    private var pulseDim = false
    private var moveSave: DispatchWorkItem?
    private var itemBoxes: [String: ItemBox] = [:]
    private var groupViews: [String: GroupFrameView] = [:]
    var linkingEnabled: Bool { model.mode == .canvas && model.maximized == nil && model.tileCount > 1 }
    var allowsDrag: Bool { model.mode == .canvas && model.maximized == nil && !model.canvasLocked }
    var showsDots: Bool { false }
    private var linkSource: SessionBox?
    private var panStart: NSPoint?

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        for glow in [glowTop, glowBottom] {
            glow.type = .radial
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            layer?.addSublayer(glow)
        }
        layer?.addSublayer(linksLayer)
        layer?.addSublayer(linkPreview)
        linksLayer.fillColor = nil
        miniMap.canvas = self
        miniMap.isHidden = true
        addSubview(miniMap)
        model.onSnap = { [weak self] number, zone in self?.snap(number, to: zone) }
        model.onMoveFocus = { [weak self] direction in self?.moveFocus(direction) }
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
        guard model.mode == .canvas, model.maximized == nil else { return }
        _ = Wallpaper.draw(in: dirtyRect, bounds: bounds)
        guard SettingsStore.shared.settings.canvasDots else { return }
        (Theme.isLight ? NSColor.black.withAlphaComponent(0.04) : NSColor.white.withAlphaComponent(0.028)).setFill()
        let step: CGFloat = 48 * model.zoom
        var x = dirtyRect.minX - dirtyRect.minX.truncatingRemainder(dividingBy: step) + pan.x.truncatingRemainder(dividingBy: step)
        while x < dirtyRect.maxX {
            NSRect(x: x, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
            x += step
        }
        var y = dirtyRect.minY - dirtyRect.minY.truncatingRemainder(dividingBy: step) + pan.y.truncatingRemainder(dividingBy: step)
        while y < dirtyRect.maxY {
            NSRect(x: dirtyRect.minX, y: y, width: dirtyRect.width, height: 1).fill()
            y += step
        }
    }

    /// Two still lights in opposite corners of the surface.
    private func placeGlows() {
        let palette = Theme.palette
        let visible = Neon.on && model.mode == .canvas && model.maximized == nil && model.tileCount > 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowTop.isHidden = !visible
        glowBottom.isHidden = !visible
        if visible {
            glowTop.colors = [palette.need.withAlphaComponent(0.12).cgColor, palette.need.withAlphaComponent(0).cgColor]
            glowBottom.colors = [palette.g1.withAlphaComponent(0.14).cgColor, palette.g1.withAlphaComponent(0).cgColor]
            glowTop.frame = CGRect(x: bounds.maxX - 340, y: -340, width: 680, height: 680)
            glowBottom.frame = CGRect(x: -340, y: bounds.maxY - 340, width: 680, height: 680)
            glowTop.opacity = Neon.opacity
            glowBottom.opacity = Neon.opacity
        }
        CATransaction.commit()
    }

    private func placeMiniMap() {
        let visible = SettingsStore.shared.settings.showMiniMap && model.mode == .canvas && model.maximized == nil && model.state.freeLayout && model.tileCount > 1
        miniMap.isHidden = !visible
        guard visible else { return }
        miniMap.frame = NSRect(x: bounds.maxX - 190 - 16, y: bounds.maxY - 112 - 16, width: 190, height: 112)
        addSubview(miniMap, positioned: .above, relativeTo: nil)
        miniMap.needsDisplay = true
    }

    /// The dot of a running session breathes about once a second, not sixty times.
    private func updatePulse() {
        let running = boxes.values.contains { $0.isRunning && !$0.isHidden && !$0.badge.isHidden }
        if running, pulseTimer == nil, Motion.allowed {
            let timer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in self?.pulse() }
            timer.tolerance = 0.2
            pulseTimer = timer
        } else if !running || !Motion.allowed, let timer = pulseTimer {
            timer.invalidate()
            pulseTimer = nil
            boxes.values.forEach { $0.badge.icon.layer?.opacity = 1 }
        }
    }

    private func pulse() {
        guard Motion.allowed else { updatePulse(); return }
        pulseDim.toggle()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        for box in boxes.values where box.isRunning && !box.isHidden {
            box.badge.icon.layer?.opacity = pulseDim ? 0.35 : 1
        }
        CATransaction.commit()
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
        let items = model.visibleItems
        let openItems = Set(items.map(\.id))
        for (id, box) in itemBoxes where !openItems.contains(id) {
            box.removeFromSuperview()
            itemBoxes[id] = nil
        }
        for item in items where itemBoxes[item.id] == nil {
            let box = ItemBox(item: item)
            box.canvas = self
            itemBoxes[item.id] = box
            addSubview(box)
        }
        let frames = computeFrames(model.visibleSessions, items)
        let reduceMotion = !Motion.allowed
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !reduceMotion ? 0.2 : 0
            for info in sessions {
                guard let box = boxes[info.number] else { continue }
                let target = frames.boxes[info.number]
                box.isHidden = target == nil
                if let target { (animated && !reduceMotion ? box.animator() : box).frame = target }
            }
            for item in items {
                guard let box = itemBoxes[item.id] else { continue }
                let target = frames.items[item.id]
                box.isHidden = target == nil
                if let target { (animated && !reduceMotion ? box.animator() : box).frame = target }
            }
        }
        applyContent()
        placeGroups(frames: frames)
        drawLinks()
        placeGlows()
        placeMiniMap()
        updatePulse()
        needsDisplay = true
    }

    private func placeGroups(frames: (boxes: [UInt32: NSRect], items: [String: NSRect])) {
        let show = model.mode == .canvas && model.maximized == nil
        var live = Set<String>()
        for group in model.state.groups where show {
            var union: NSRect?
            for member in group.members {
                let rect = model.sessions.first { $0.id == member }.flatMap { frames.boxes[$0.number] } ?? frames.items[member]
                if let rect { union = union?.union(rect) ?? rect }
            }
            guard let union else { continue }
            live.insert(group.id)
            let view = groupViews[group.id] ?? {
                let view = GroupFrameView(group: group)
                view.canvas = self
                groupViews[group.id] = view
                addSubview(view, positioned: .below, relativeTo: nil)
                return view
            }()
            view.update(group)
            view.frame = union.insetBy(dx: -14, dy: -14).offsetBy(dx: 0, dy: -8).union(union.insetBy(dx: -14, dy: -14))
        }
        for (id, view) in groupViews where !live.contains(id) {
            view.removeFromSuperview()
            groupViews[id] = nil
        }
    }

    func applyContent() {
        let single = model.tileCount == 1 || model.maximized != nil || model.mode == .tabs
        let farAway = model.mode == .canvas && model.maximized == nil && model.zoom < 0.55
        for info in model.sessions {
            guard let box = boxes[info.number] else { continue }
            box.showsHeader = !single
            box.summaryOnly = farAway
            box.apply(info: info, focused: info.number == model.focused && !single, model: model)
            if single { box.panel.layer?.borderWidth = 0 }
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

    func computeFrames(_ sessions: [SessionInfo], _ items: [CanvasItem]) -> (boxes: [UInt32: NSRect], items: [String: NSRect]) {
        var frames: [UInt32: NSRect] = [:]
        var itemFrames: [String: NSRect] = [:]
        let area = bounds
        guard area.width > 80, area.height > 80, !(sessions.isEmpty && items.isEmpty) else { return (frames, itemFrames) }
        let full = NSRect(x: 0, y: 0, width: area.width, height: area.height)
        if sessions.count + items.count == 1 || model.maximized != nil || model.mode == .tabs {
            if let number = model.maximized ?? (model.mode == .tabs ? model.focused : sessions.first?.number) ?? sessions.first?.number {
                frames[number] = full
            } else if let item = items.first {
                itemFrames[item.id] = full
            }
            return (frames, itemFrames)
        }
        let keys: [(id: String, number: UInt32?)] = sessions.map { ($0.id, $0.number) } + items.map { ($0.id, nil) }
        func place(_ key: (id: String, number: UInt32?), _ rect: NSRect) {
            if let number = key.number { frames[number] = rect } else { itemFrames[key.id] = rect }
        }
        let count = keys.count
        if !model.state.freeLayout && count <= 6 {
            let columns = count <= 2 ? count : (count <= 4 ? 2 : 3)
            let rows = Int(ceil(Double(count) / Double(columns)))
            let gap: CGFloat = 16
            let width = (area.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
            let height = (area.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
            for (index, key) in keys.enumerated() {
                let row = index / columns
                let column = index % columns
                let rect = NSRect(x: gap + CGFloat(column) * (width + gap), y: gap + CGFloat(row) * (height + gap), width: width, height: height)
                place(key, scaled(rect, around: area))
            }
            return (frames, itemFrames)
        }
        // Seven and more, or once arranged by hand: boxes keep their size, the surface moves.
        let fallback = NSSize(width: 520, height: 320)
        for (index, key) in keys.enumerated() {
            let saved = model.state.positions[key.id]
            let size = model.state.sizes[key.id] ?? fallback
            let origin = saved ?? CGPoint(x: 16 + CGFloat(index % 3) * (size.width + 24), y: 16 + CGFloat(index / 3) * (size.height + 24))
            place(key, scaled(NSRect(origin: origin, size: size), around: area))
        }
        return (frames, itemFrames)
    }

    private func scaled(_ rect: NSRect, around area: NSRect) -> NSRect {
        let zoom = model.zoom
        return NSRect(x: rect.minX * zoom + pan.x, y: rect.minY * zoom + pan.y, width: rect.width * zoom, height: rect.height * zoom)
    }

    func fit() {
        model.pushLayoutUndo()
        pan = .zero
        model.state.freeLayout = false
        model.state.positions.removeAll()
        model.state.sizes.removeAll()
        model.setZoom(1)
        model.saveState()
    }

    /// The first move by hand turns the automatic tiles into free positions, without anything jumping.
    func freezeLayout() {
        guard !model.state.freeLayout else { return }
        let zoom = model.zoom
        func store(_ id: String, _ frame: NSRect) {
            model.state.positions[id] = CGPoint(x: (frame.minX - pan.x) / zoom, y: (frame.minY - pan.y) / zoom)
            model.state.sizes[id] = CGSize(width: frame.width / zoom, height: frame.height / zoom)
        }
        for session in model.visibleSessions {
            if let box = boxes[session.number] { store(session.id, box.frame) }
        }
        for item in model.visibleItems {
            if let box = itemBoxes[item.id] { store(item.id, box.frame) }
        }
        model.state.freeLayout = true
    }

    private func snapped(_ origin: NSPoint) -> NSPoint {
        guard SettingsStore.shared.settings.snapToGrid else { return origin }
        let step = 24 * model.zoom
        return NSPoint(x: ((origin.x - pan.x) / step).rounded() * step + pan.x, y: ((origin.y - pan.y) / step).rounded() * step + pan.y)
    }

    func moveBox(_ box: SessionBox, to origin: NSPoint) {
        guard let info = model.sessions.first(where: { $0.number == box.number }) else { return }
        freezeLayout()
        let target = snapped(origin)
        box.frame.origin = target
        model.state.positions[info.id] = CGPoint(x: (target.x - pan.x) / model.zoom, y: (target.y - pan.y) / model.zoom)
        afterMove()
    }

    func resizeBox(_ box: SessionBox, to size: NSSize) {
        guard let info = model.sessions.first(where: { $0.number == box.number }) else { return }
        freezeLayout()
        let target = NSSize(width: max(280 * model.zoom, size.width), height: max(160 * model.zoom, size.height))
        box.frame.size = target
        model.state.sizes[info.id] = CGSize(width: target.width / model.zoom, height: target.height / model.zoom)
        box.layoutContents(host: model.hosts[box.number], fontScale: model.zoom)
        afterMove()
    }

    func origin(ofItem id: String) -> NSPoint? { itemBoxes[id]?.frame.origin }
    func frame(ofItem id: String) -> NSRect? { itemBoxes[id]?.frame }

    func moveItem(_ id: String, to origin: NSPoint) {
        guard let box = itemBoxes[id] else { return }
        freezeLayout()
        let target = snapped(origin)
        box.frame.origin = target
        model.state.positions[id] = CGPoint(x: (target.x - pan.x) / model.zoom, y: (target.y - pan.y) / model.zoom)
        afterMove()
    }

    func resizeItem(_ id: String, to size: NSSize) {
        guard let box = itemBoxes[id] else { return }
        freezeLayout()
        let target = NSSize(width: max(240 * model.zoom, size.width), height: max(160 * model.zoom, size.height))
        box.frame.size = target
        model.state.sizes[id] = CGSize(width: target.width / model.zoom, height: target.height / model.zoom)
        afterMove()
    }

    func moveGroup(_ group: CanvasGroup, by delta: NSPoint) {
        freezeLayout()
        for member in group.members {
            if let current = model.state.positions[member] {
                model.state.positions[member] = CGPoint(x: current.x + delta.x / model.zoom, y: current.y + delta.y / model.zoom)
            }
        }
        relayout(animated: false)
    }

    private func afterMove() {
        drawLinks()
        placeMiniMap()
        placeGroups(frames: (boxes.compactMapValues { $0.isHidden ? nil : $0.frame }, itemBoxes.compactMapValues { $0.isHidden ? nil : $0.frame }))
        moveSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.model.saveState() }
        moveSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// One half of the surface, by key or from the menu.
    func snap(_ number: UInt32, to zone: SnapZone) {
        guard model.mode == .canvas, model.maximized == nil, model.tileCount > 1, let info = model.sessions.first(where: { $0.number == number }) else { return }
        model.pushLayoutUndo()
        freezeLayout()
        let gap: CGFloat = 16
        let width = (bounds.width - gap * 2) / model.zoom, height = (bounds.height - gap * 2) / model.zoom
        let left = (gap - pan.x) / model.zoom, top = (gap - pan.y) / model.zoom
        var rect: NSRect
        switch zone {
        case .left: rect = NSRect(x: left, y: top, width: (width - gap) / 2, height: height)
        case .right: rect = NSRect(x: left + (width + gap) / 2, y: top, width: (width - gap) / 2, height: height)
        case .top: rect = NSRect(x: left, y: top, width: width, height: (height - gap) / 2)
        case .bottom: rect = NSRect(x: left, y: top + (height + gap) / 2, width: width, height: (height - gap) / 2)
        }
        rect = rect.integral
        model.state.positions[info.id] = rect.origin
        model.state.sizes[info.id] = rect.size
        relayout(animated: true)
        model.saveState()
    }

    /// The nearest box in a direction. Nothing moves, only the keyboard does.
    func moveFocus(_ direction: SnapZone) {
        guard let number = model.focused, let current = boxes[number]?.frame else { return }
        var best: (UInt32, CGFloat)?
        for info in model.visibleSessions where info.number != number {
            guard let frame = boxes[info.number]?.frame, boxes[info.number]?.isHidden == false else { continue }
            let dx = frame.midX - current.midX, dy = frame.midY - current.midY
            let fits: Bool
            switch direction {
            case .left: fits = dx < 0 && abs(dx) >= abs(dy) / 2
            case .right: fits = dx > 0 && abs(dx) >= abs(dy) / 2
            case .top: fits = dy < 0 && abs(dy) >= abs(dx) / 2
            case .bottom: fits = dy > 0 && abs(dy) >= abs(dx) / 2
            }
            guard fits else { continue }
            let distance = hypot(dx, dy)
            if best == nil || distance < best?.1 ?? .greatestFiniteMagnitude { best = (info.number, distance) }
        }
        if let best {
            model.setFocus(best.0)
            if model.maximized != nil { model.maximized = best.0; model.onLayoutChange?() }
        }
    }

    override func layout() {
        super.layout()
        relayout(animated: false)
    }

    // MARK: Empty surface

    override func menu(for event: NSEvent) -> NSMenu? { CanvasMenus.canvas() }

    override func mouseDown(with event: NSEvent) {
        if let link = link(at: convert(event.locationInWindow, from: nil)) {
            model.overlay = .linkDetail(link.id)
            return
        }
        panStart = event.locationInWindow
    }

    /// A click near a line opens its details.
    private func link(at point: NSPoint) -> SessionLink? {
        guard model.mode == .canvas, model.maximized == nil else { return nil }
        return linkRoutes.first { LinkRoute.distance(from: point, to: $0.route) < 12 }?.link
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
        addRoute(LinkRoute.points(from: source.frame, to: CGRect(origin: point, size: .zero)), to: path)
        linkPreview.strokeColor = Theme.palette.fg.cgColor
        linkPreview.path = path
        for box in boxes.values where box !== source {
            box.panel.layer?.borderColor = box.frame.contains(point) ? Theme.palette.need.cgColor : Theme.palette.line2.cgColor
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

    /// Straight runs and soft corners, with the head of the Enter key at the far end.
    private func addRoute(_ route: [CGPoint], to path: CGMutablePath) {
        guard let first = route.first, let last = route.last, route.count > 1 else { return }
        path.move(to: first)
        for index in 1..<max(1, route.count - 1) {
            let corner = route[index], next = route[index + 1], previous = route[index - 1]
            let room = min(hypot(corner.x - previous.x, corner.y - previous.y), hypot(next.x - corner.x, next.y - corner.y)) / 2
            path.addArc(tangent1End: corner, tangent2End: next, radius: min(10, room))
        }
        path.addLine(to: last)
        let before = route[route.count - 2]
        let direction: CGFloat = last.x >= before.x ? 1 : -1
        path.move(to: CGPoint(x: last.x - 8 * direction, y: last.y - 6))
        path.addLine(to: last)
        path.addLine(to: CGPoint(x: last.x - 8 * direction, y: last.y + 6))
    }

    func drawLinks() {
        let palette = Theme.palette
        linksLayer.frame = bounds
        linkPreview.frame = bounds
        linksLayer.strokeColor = palette.g1.cgColor
        linksLayer.lineWidth = 1.5
        linksLayer.lineCap = .round
        linksLayer.lineJoin = .round
        let path = CGMutablePath()
        linkRoutes.removeAll()
        if model.mode == .canvas, model.maximized == nil {
            for link in LinkStore.shared.links {
                guard let from = model.sessions.first(where: { $0.id == link.from }), let to = model.sessions.first(where: { $0.id == link.to }),
                      let a = boxes[from.number], let b = boxes[to.number], !a.isHidden, !b.isHidden else { continue }
                let route = LinkRoute.points(from: a.frame, to: b.frame)
                linkRoutes.append((link, route))
                addRoute(route, to: path)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        linksLayer.path = path
        linksLayer.zPosition = 10
        linksLayer.shadowColor = palette.g1.cgColor
        linksLayer.shadowRadius = 3
        linksLayer.shadowOffset = .zero
        linksLayer.shadowOpacity = Neon.on ? 0.8 : 0
        linksLayer.shadowPath = path.isEmpty ? nil : path.copy(strokingWithWidth: 1.5, lineCap: .round, lineJoin: .round, miterLimit: 4)
        placeLinkLabels()
        CATransaction.commit()
    }

    private func placeLinkLabels() {
        let palette = Theme.palette
        while linkLabels.count < linkRoutes.count {
            let label = CATextLayer()
            label.string = "Bağlam"
            label.font = NSFont.systemFont(ofSize: 11)
            label.fontSize = 11
            label.alignmentMode = .center
            label.cornerRadius = 5
            label.zPosition = 11
            layer?.addSublayer(label)
            linkLabels.append(label)
        }
        for (index, label) in linkLabels.enumerated() {
            guard index < linkRoutes.count else { label.isHidden = true; continue }
            let route = linkRoutes[index].route
            // On the longest straight run, where it covers no corner.
            var best = (a: route[0], b: route[1])
            for (p, q) in zip(route, route.dropFirst()) where hypot(q.x - p.x, q.y - p.y) > hypot(best.b.x - best.a.x, best.b.y - best.a.y) { best = (p, q) }
            label.isHidden = false
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.foregroundColor = palette.g1.cgColor
            label.backgroundColor = palette.surface0.cgColor
            label.frame = CGRect(x: (best.a.x + best.b.x) / 2 - 26, y: (best.a.y + best.b.y) / 2 - 8, width: 52, height: 16)
        }
    }

    /// One pass of light along the session's lines, when it starts working. Nothing stays behind.
    func flowLinks(of sessionID: String) {
        guard Motion.allowed, Neon.on else { return }
        for item in linkRoutes where item.link.from == sessionID || item.link.to == sessionID {
            let path = CGMutablePath()
            guard let first = item.route.first else { continue }
            path.move(to: first)
            for point in item.route.dropFirst() { path.addLine(to: point) }
            let length = zip(item.route, item.route.dropFirst()).reduce(CGFloat(0)) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            let light = CAShapeLayer()
            light.frame = bounds
            light.path = path
            light.fillColor = nil
            light.strokeColor = NSColor.white.cgColor
            light.lineWidth = 2
            light.lineCap = .round
            light.lineDashPattern = [18, NSNumber(value: Double(length + 40))]
            light.lineDashPhase = -length - 20
            light.zPosition = 12
            layer?.addSublayer(light)
            CATransaction.begin()
            CATransaction.setCompletionBlock { light.removeFromSuperlayer() }
            let run = CABasicAnimation(keyPath: "lineDashPhase")
            run.fromValue = 18
            run.toValue = -length - 20
            run.duration = 1.2
            light.add(run, forKey: "flow")
            CATransaction.commit()
        }
    }
}
