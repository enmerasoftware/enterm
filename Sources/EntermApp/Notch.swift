import AppKit
import EntermCore
import SwiftUI

/// The sessions at the top of the screen, around the MacBook notch. It exists only while a program runs,
/// redraws only when a state changes, and takes the keyboard from nobody.
final class NotchCenter: ObservableObject {
    static let shared = NotchCenter()
    @Published var expanded = false
    private var panel: NSPanel?
    private var collapseWork: DispatchWorkItem?

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
            return
        }
        if panel == nil { makePanel() }
        place()
        objectWillChange.send()
    }

    private func makePanel() {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
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
    var height: CGFloat { barHeight }

    private func place() {
        guard let panel, let screen else { return }
        let count = AppModel.shared.sessions.filter { $0.tool != .terminal }.count
        let width = expanded ? max(360, notchWidth + 80) : notchWidth + 2 * 52
        let listHeight = CGFloat(min(count, 6)) * 40 + 16
        let height = barHeight + (expanded ? listHeight : 0)
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hover(_ inside: Bool) {
        collapseWork?.cancel()
        if inside {
            if !expanded {
                expanded = true
                place()
            }
        } else {
            // A short delay, so the list survives the mouse crossing its edge.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.expanded = false
                self.place()
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    func open(_ number: UInt32) {
        expanded = false
        place()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.contentView is RootView }?.makeKeyAndOrderFront(nil)
        let model = AppModel.shared
        model.page = nil
        model.setFocus(number)
        if model.maximized != nil { model.maximized = number }
        model.onLayoutChange?()
    }
}

private struct NotchView: View {
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
                    ForEach(agents.filter { $0.status == .running }.prefix(3)) { _ in dot(palette.g1) }
                    if agents.allSatisfy({ $0.status != .running }) { dot(NSColor.white.withAlphaComponent(0.3)) }
                }
                .frame(width: 44)
                Spacer(minLength: center.gap)
                HStack(spacing: 4) {
                    let waiting = agents.filter { Neon.color($0.status) != nil && $0.status != .running }
                    if waiting.isEmpty {
                        Text("\(agents.count)").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.6))
                    } else {
                        ForEach(waiting.prefix(3)) { info in dot(Neon.color(info.status) ?? palette.need) }
                    }
                }
                .frame(width: 44)
            }
            .frame(height: center.height)
            if center.expanded {
                VStack(spacing: 0) {
                    ForEach(agents.prefix(6)) { info in
                        Button { center.open(info.number) } label: {
                            HStack(spacing: 10) {
                                dot(Neon.color(info.status) ?? NSColor.white.withAlphaComponent(0.3))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(model.name(for: info)).font(.system(size: 12, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                                    Text(info.status.title).font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Text("Git ⏎").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .clipShape(BottomRounded(radius: center.expanded ? 16 : 10))
        .onHover { center.hover($0) }
    }

    private func dot(_ color: NSColor) -> some View {
        Circle().fill(Color(color)).frame(width: 8, height: 8).shadow(color: Color(color).opacity(0.8), radius: 3)
    }
}

private struct BottomRounded: Shape {
    let radius: CGFloat
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
