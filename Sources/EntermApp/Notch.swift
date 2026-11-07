import AppKit
import EntermCore
import SwiftUI

/// The sessions at the top of the screen, around the MacBook notch. It exists only while a program runs,
/// redraws only when a state changes, and takes the keyboard from nobody.
final class NotchCenter: ObservableObject {
    static let shared = NotchCenter()
    @Published var expanded = false
    private var panel: NSPanel?
#if ENTERM_TEST_DRIVER
    var debugView: NSView? { panel?.contentView }
#endif
    private var collapseWork: DispatchWorkItem?
    /// The panel stays at the open size until the capsule has finished shrinking inside it.
    private var panelOpen = false
    private var shrinkWork: DispatchWorkItem?

    /// A soft spring, so the capsule grows out of the notch instead of jumping.
    private var motion: Animation? {
        guard SettingsStore.shared.settings.motion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return nil }
        return .spring(response: 0.42, dampingFraction: 0.84)
    }

    private var wanted: Bool {
        guard SettingsStore.shared.settings.notch, !PowerCenter.shared.settings.lowPower else { return false }
        let environment = ProcessInfo.processInfo.environment
        // A test run never draws on the person's screen unless it asks to.
        if environment["ENTERM_DEBUG_DIR"] != nil, environment["ENTERM_NOTCH_TEST"] == nil { return false }
        return AppModel.shared.sessions.contains { $0.tool != .terminal }
    }

    func update() {
        guard wanted else {
            panel?.orderOut(nil)
            panel = nil
            expanded = false
            panelOpen = false
            return
        }
        if panel == nil { makePanel() }
        place()
        objectWillChange.send()
    }

    private func makePanel() {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        // After the line above: it sets the floating level, and a floating window is pushed below the menu bar.
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: NotchView())
        host.safeAreaRegions = []
        panel.contentView = host
        self.panel = panel
    }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private var notchWidth: CGFloat {
        guard let screen, screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea?.width, let right = screen.auxiliaryTopRightArea?.width else { return 0 }
        return screen.frame.width - left - right
    }

    private var barHeight: CGFloat {
        guard let screen else { return 28 }
        return screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : max(24, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    /// The middle of the capsule, where the notch hides it.
    var gap: CGFloat { notchWidth }
    /// Each side of the capsule beside the notch. The dots keep this place when the list opens.
    let side: CGFloat = 52
    static let rowHeight: CGFloat = 40
    var height: CGFloat { barHeight }

    var closedWidth: CGFloat { notchWidth + 2 * side }
    var openWidth: CGFloat { max(360, closedWidth) }

    private func place() {
        guard let panel, let screen else { return }
        let count = AppModel.shared.sessions.filter { $0.tool != .terminal }.count
        let open = expanded || panelOpen
        let width = open ? openWidth : closedWidth
        // MenuList: rows with its gap between them and 10 on every side.
        let rows = CGFloat(min(count, 6))
        let listHeight = rows * Self.rowHeight + max(rows - 1, 0) * MenuList<EmptyView>.gap + 20
        let height = barHeight + (open ? listHeight : 0)
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hover(_ inside: Bool) {
        collapseWork?.cancel()
        if inside {
            if !expanded { setExpanded(true) }
        } else {
            // A short delay, so the list survives the mouse crossing its edge.
            let work = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    /// Opening makes room first and then grows the capsule into it; closing shrinks the capsule first
    /// and gives the room back once it is small again.
    private func setExpanded(_ value: Bool) {
        shrinkWork?.cancel()
        if value {
            panelOpen = true
            place()
            withAnimation(motion) { expanded = true }
        } else {
            withAnimation(motion) { expanded = false }
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.expanded else { return }
                self.panelOpen = false
                self.place()
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (motion == nil ? 0 : 0.5), execute: work)
        }
    }

    func open(_ number: UInt32) {
        collapseWork?.cancel()
        setExpanded(false)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.contentView is RootView }?.makeKeyAndOrderFront(nil)
        let model = AppModel.shared
        model.page = nil
        model.setFocus(number)
        if model.maximized != nil { model.maximized = number }
        model.onLayoutChange?()
    }
}

/// Sits on the top edge of the screen, in the menu bar's band, around the notch.
private final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private struct NotchView: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var center = NotchCenter.shared
    @ObservedObject var model = AppModel.shared

    private var agents: [SessionInfo] {
        RailOrder.sorted(model.sessions.filter { $0.tool != .terminal }) { $0.status }
    }

    var body: some View {
        let palette = Theme.palette
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(agents.filter { $0.status == .running }.prefix(3)) { _ in Self.dot(palette.g1) }
                    if agents.allSatisfy({ $0.status != .running }) { Self.dot(NSColor.white.withAlphaComponent(0.3)) }
                }
                .frame(width: center.side)
                Spacer(minLength: center.gap)
                HStack(spacing: 4) {
                    let waiting = agents.filter { Neon.color($0.status) != nil && $0.status != .running }
                    if waiting.isEmpty {
                        Text("\(agents.count)").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.6))
                    } else {
                        ForEach(waiting.prefix(3)) { info in Self.dot(Neon.color(info.status) ?? palette.need) }
                    }
                }
                .frame(width: center.side)
            }
            // As wide as the closed capsule, so the dots do not move when the list opens.
            .frame(width: center.gap + 2 * center.side, height: center.height)
            if center.expanded {
                MenuList {
                    ForEach(agents.prefix(6)) { info in
                        NotchRow(info: info)
                    }
                }
                .frame(width: center.openWidth)
                .transition(.opacity.combined(with: .offset(y: -10)))
            }
        }
        // The capsule grows inside a panel that already has room for it, so the edge moves smoothly.
        .frame(width: center.expanded ? center.openWidth : center.closedWidth, alignment: .top)
        .background(Color.black)
        .clipShape(BottomRounded(radius: center.expanded ? 16 : 10))
        .overlay(NotchScan(lit: NotchScan.lit(working: agents.contains { $0.status == .running }), color: palette.g1, radius: center.expanded ? 16 : 10).allowsHitTesting(false))
        .onHover { center.hover($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    static func dot(_ color: NSColor) -> some View {
        Circle().fill(Color(color)).frame(width: 8, height: 8).shadow(color: Color(color).opacity(0.8), radius: 3)
    }
}

/// One session in the open notch. White on black, so the hover fill is white too.
private struct NotchRow: View {
    let info: SessionInfo
    @ObservedObject var center = NotchCenter.shared
    @ObservedObject var model = AppModel.shared
    @State private var hovering = false
    var body: some View {
        Button { center.open(info.number) } label: {
            HStack(spacing: 10) {
                NotchView.dot(Neon.color(info.status) ?? NSColor.white.withAlphaComponent(0.3))
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name(for: info)).font(.system(size: 12, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                    Text(info.status.title).font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("Git ⏎").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .frame(height: NotchCenter.rowHeight)
            .background(hovering ? Color.white.opacity(0.1) : .clear)
            .cornerRadius(Theme.cornerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}

private struct BottomRounded: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// While a program works, a light runs along the capsule's edge, like the one round a working box.
/// The turn is Core Animation's: nothing is drawn per frame.
private struct NotchScan: NSViewRepresentable {
    /// Every input is a field, so a change of the glow or motion setting reaches the view too.
    let lit: Bool
    let color: NSColor
    let radius: CGFloat

    static func lit(working: Bool) -> Bool {
        working && Neon.on && SettingsStore.shared.settings.motion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func makeNSView(context: Context) -> NotchScanView { NotchScanView() }
    func updateNSView(_ view: NotchScanView, context: Context) {
        view.radius = radius
        view.apply(lit: lit, color: color)
    }
}

private final class NotchScanView: NSView {
    private let light = CAGradientLayer()
    private let mask = CAShapeLayer()
    var radius: CGFloat = 10 { didSet { if radius != oldValue { needsLayout = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        light.type = .conic
        light.startPoint = CGPoint(x: 0.5, y: 0.5)
        light.endPoint = CGPoint(x: 0.5, y: 0)
        light.locations = [0, 0.13, 0.26, 0.5, 0.63, 0.76, 1]
        mask.fillColor = nil
        mask.strokeColor = NSColor.black.cgColor
        mask.lineWidth = 1.5
        mask.shadowColor = NSColor.black.cgColor
        mask.shadowOffset = .zero
        mask.shadowOpacity = 1
        layer?.addSublayer(light)
        layer?.mask = mask
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(lit: Bool, color: NSColor) {
        isHidden = !lit
        guard lit else {
            light.removeAnimation(forKey: "scan")
            return
        }
        light.colors = [color.withAlphaComponent(0).cgColor, color.cgColor, color.withAlphaComponent(0).cgColor,
                        color.withAlphaComponent(0).cgColor, color.cgColor, color.withAlphaComponent(0).cgColor,
                        color.withAlphaComponent(0).cgColor]
        light.opacity = Neon.opacity
        mask.shadowRadius = Neon.radius
        guard light.animation(forKey: "scan") == nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = -2 * CGFloat.pi
        turn.duration = 3.2
        turn.repeatCount = .infinity
        turn.isRemovedOnCompletion = false
        light.add(turn, forKey: "scan")
    }

    /// The sides and the rounded bottom. The top is the screen's edge, so it has no line.
    override func layout() {
        super.layout()
        let width = bounds.width, height = bounds.height
        guard width > 0, height > 0 else { return }
        // Inside the capsule by half a line, so the window's edge does not cut the light in two.
        let inset: CGFloat = 0.75, r = min(radius, height / 2)
        let path = CGMutablePath()
        // The layer counts upwards: the capsule's bottom is y = 0.
        path.move(to: CGPoint(x: inset, y: height))
        path.addLine(to: CGPoint(x: inset, y: inset + r))
        path.addQuadCurve(to: CGPoint(x: inset + r, y: inset), control: CGPoint(x: inset, y: inset))
        path.addLine(to: CGPoint(x: width - inset - r, y: inset))
        path.addQuadCurve(to: CGPoint(x: width - inset, y: inset + r), control: CGPoint(x: width - inset, y: inset))
        path.addLine(to: CGPoint(x: width - inset, y: height))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        mask.path = path
        mask.shadowPath = path.copy(strokingWithWidth: 1.5, lineCap: .round, lineJoin: .round, miterLimit: 4)
        let side = ceil(hypot(width, height))
        light.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        light.position = CGPoint(x: width / 2, y: height / 2)
        CATransaction.commit()
    }
}
