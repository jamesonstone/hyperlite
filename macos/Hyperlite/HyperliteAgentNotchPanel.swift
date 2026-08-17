import AppKit
import Combine
import SwiftUI

@MainActor
final class HyperliteAgentNotchCoordinator {
    private let state: HyperliteAgentSessionState
    private var panel: HyperliteAgentNotchPanel?
    private var screenObserver: NSObjectProtocol?
    private var expanded = false

    init(state: HyperliteAgentSessionState? = nil) {
        self.state = state ?? .shared
    }

    func start() {
        guard HyperliteFeatureFlags.agentSessionPresentation, panel == nil else { return }
        state.start()
        createPanel()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        expanded = false
    }

    private func createPanel() {
        guard let screen = targetScreen() else { return }
        let geometry = HyperliteAgentNotchGeometry(screenFrame: screen.frame, metrics: screen.hyperliteAgentNotchMetrics)
        let panel = HyperliteAgentNotchPanel(contentRect: geometry.frame(expanded: false))
        let view = HyperliteAgentNotchView(
            state: state,
            onExpansionChanged: { [weak self] expanded in self?.setExpanded(expanded) },
            onOpenWindow: { Self.openMainWindow() }
        )
        panel.contentViewController = NSHostingController(rootView: view.hyperliteTheme())
        panel.setFrame(geometry.frame(expanded: false), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func setExpanded(_ expanded: Bool) {
        guard self.expanded != expanded, let panel, let screen = targetScreen() else { return }
        self.expanded = expanded
        let geometry = HyperliteAgentNotchGeometry(screenFrame: screen.frame, metrics: screen.hyperliteAgentNotchMetrics)
        panel.setFrame(
            geometry.frame(expanded: expanded, hasSessions: state.snapshot?.sessions.isEmpty == false),
            display: true,
            animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        if expanded { panel.makeKey() } else { panel.resignKey() }
    }

    private func reposition() {
        guard let panel, let screen = targetScreen() else { return }
        let geometry = HyperliteAgentNotchGeometry(screenFrame: screen.frame, metrics: screen.hyperliteAgentNotchMetrics)
        panel.setFrame(
            geometry.frame(expanded: expanded, hasSessions: state.snapshot?.sessions.isEmpty == false),
            display: true
        )
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "Hyperlite" })?.makeKeyAndOrderFront(nil)
        HyperliteState.shared.showWorkspace(.sessions)
    }
}

final class HyperliteAgentNotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 2
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
