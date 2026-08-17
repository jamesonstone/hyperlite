import AppKit
import Combine
import SwiftUI

@MainActor
final class HyperliteAgentNotchCoordinator {
    private let state: HyperliteAgentSessionState
    private let display = HyperliteAgentNotchDisplayState()
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
        display.hasCompanionFocus = false
    }

    private func createPanel() {
        guard let screen = targetScreen() else { return }
        let geometry = HyperliteAgentNotchGeometry(screenFrame: screen.frame, metrics: screen.hyperliteAgentNotchMetrics)
        display.hasPhysicalNotch = geometry.metrics.hasPhysicalNotch
        let panel = HyperliteAgentNotchPanel(
            contentRect: geometry.frame(expanded: false),
            hasPhysicalNotch: geometry.metrics.hasPhysicalNotch
        )
        panel.onKeyStatusChanged = { [weak display] focused in
            display?.hasCompanionFocus = focused
        }
        let view = HyperliteAgentNotchView(
            state: state,
            display: display,
            onExpansionChanged: { [weak self] expanded, activate in
                self?.setExpanded(expanded, activate: activate)
            },
            onRequestFocus: { [weak self] in self?.focusCompanion() },
            onOpenWindow: { Self.openMainWindow() }
        )
        panel.contentViewController = NSHostingController(rootView: view.hyperliteTheme())
        panel.setFrame(geometry.frame(expanded: false), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func setExpanded(_ expanded: Bool, activate: Bool) {
        guard self.expanded != expanded, let panel, let screen = targetScreen() else { return }
        self.expanded = expanded
        let geometry = HyperliteAgentNotchGeometry(screenFrame: screen.frame, metrics: screen.hyperliteAgentNotchMetrics)
        updateDisplay(for: geometry, panel: panel)
        panel.setFrame(
            geometry.frame(expanded: expanded, hasSessions: state.snapshot?.sessions.isEmpty == false),
            display: true,
            animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        if !expanded { panel.resignKey() } else if activate { panel.makeKey() }
    }

    private func focusCompanion() {
        guard expanded else { return }
        panel?.makeKey()
    }

    private func reposition() {
        guard let panel, let screen = targetScreen() else { return }
        let geometry = HyperliteAgentNotchGeometry(screenFrame: screen.frame, metrics: screen.hyperliteAgentNotchMetrics)
        updateDisplay(for: geometry, panel: panel)
        panel.setFrame(
            geometry.frame(expanded: expanded, hasSessions: state.snapshot?.sessions.isEmpty == false),
            display: true
        )
    }

    private func updateDisplay(
        for geometry: HyperliteAgentNotchGeometry,
        panel: HyperliteAgentNotchPanel
    ) {
        display.hasPhysicalNotch = geometry.metrics.hasPhysicalNotch
        panel.setPhysicalNotch(geometry.metrics.hasPhysicalNotch)
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

@MainActor
final class HyperliteAgentNotchDisplayState: ObservableObject {
    @Published var hasPhysicalNotch = false
    @Published var hasCompanionFocus = false
}

final class HyperliteAgentNotchPanel: NSPanel {
    var onKeyStatusChanged: ((Bool) -> Void)?

    init(contentRect: CGRect, hasPhysicalNotch: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = !hasPhysicalNotch
        level = .mainMenu + 2
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        onKeyStatusChanged?(true)
    }

    override func resignKey() {
        super.resignKey()
        onKeyStatusChanged?(false)
    }

    func setPhysicalNotch(_ value: Bool) {
        hasShadow = !value
        invalidateShadow()
    }
}
