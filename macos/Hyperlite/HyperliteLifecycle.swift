import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class HyperliteApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var hotKey: HyperliteHotKeyController?
    private var agentNotch: HyperliteAgentNotchCoordinator?
    private var agentConsentObserver: AnyCancellable?
    private weak var window: NSWindow?
    private var terminationPending = false
    private var dailyDateObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = HyperliteHotKeyController { [weak self] in
            HyperliteState.shared.refreshAll()
            self?.showWindow()
        }
        hotKey?.start()
        dailyDateObservers = [
            Notification.Name.NSCalendarDayChanged,
            Notification.Name.NSSystemClockDidChange,
            Notification.Name.NSSystemTimeZoneDidChange,
        ].map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    HyperliteState.shared.refreshDailyNoteDateIfNeeded()
                }
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.window = NSApp.windows.first(where: { $0.title == "Hyperlite" })
            self?.window?.delegate = self
            if HyperliteFeatureFlags.agentSessionPresentation {
                let sessionState = HyperliteAgentSessionState.shared
                let coordinator = HyperliteAgentNotchCoordinator()
                self?.agentNotch = coordinator
                self?.agentConsentObserver = sessionState.$hasConsent
                    .removeDuplicates()
                    .sink { [weak self] hasConsent in
                        if hasConsent {
                            self?.agentNotch?.start()
                        } else {
                            self?.agentNotch?.stop()
                            sessionState.prepareOnboarding()
                        }
                    }
                if sessionState.hasConsent {
                    self?.window?.orderOut(nil)
                } else {
                    HyperliteState.shared.showWorkspace(.sessions)
                    self?.showWindow()
                }
            } else {
                self?.showWindow()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        HyperliteState.shared.refreshAllIfStale()
        HyperliteAgentSessionState.shared.refreshSessionsIfStale()
    }

    func applicationDidResignActive(_ notification: Notification) {
        Task { await HyperliteNotepadState.shared.flush() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard HyperliteNotepadState.shared.isDirty || HyperliteNotepadState.shared.isSaving else {
            return .terminateNow
        }
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        Task { [weak self] in
            let saved = await HyperliteNotepadState.shared.flush()
            self?.terminationPending = false
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        dailyDateObservers.forEach(NotificationCenter.default.removeObserver)
        dailyDateObservers.removeAll()
        hotKey?.stop()
        agentNotch?.stop()
        agentNotch = nil
        agentConsentObserver?.cancel()
        agentConsentObserver = nil
        HyperliteAgentSessionState.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { await HyperliteNotepadState.shared.flush() }
        sender.orderOut(nil)
        return false
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let target = window ?? NSApp.windows.first(where: { $0.title == "Hyperlite" })
        target?.makeKeyAndOrderFront(nil)
    }
}

private final class HyperliteHotKeyController {
    private let action: () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var defaultsObserver: NSObjectProtocol?
    private var lastTrigger = Date.distantPast

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func start() {
        guard eventHandler == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<HyperliteHotKeyController>.fromOpaque(userData).takeUnretainedValue().trigger()
                return noErr
            },
            1,
            &eventSpec,
            context,
            &eventHandler
        )
        registerCurrentShortcut()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerCurrentShortcut()
        }
    }

    func stop() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        hotKeyRef = nil
        eventHandler = nil
        defaultsObserver = nil
    }

    private func registerCurrentShortcut() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let text = UserDefaults.standard.string(forKey: "hyperlite.hotkey") ?? defaultHotKey
        let shortcut = HyperliteShortcut.parse(text) ?? HyperliteShortcut.default
        var ref: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: fourCharCode("HLIT"), id: 1)
        guard RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &ref
        ) == noErr else { return }
        hotKeyRef = ref
    }

    private func trigger() {
        let now = Date()
        guard now.timeIntervalSince(lastTrigger) > 0.2 else { return }
        lastTrigger = now
        DispatchQueue.main.async(execute: action)
    }

    deinit { stop() }
}

private struct HyperliteShortcut {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = HyperliteShortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey | shiftKey))

    static func parse(_ text: String) -> HyperliteShortcut? {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let key = parts.last, key.count == 1, let scalar = key.unicodeScalars.first else { return nil }
        let keyCodes: [UnicodeScalar: UInt32] = [
            "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C), "d": UInt32(kVK_ANSI_D),
            "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F), "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H),
            "i": UInt32(kVK_ANSI_I), "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O), "p": UInt32(kVK_ANSI_P),
            "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R), "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T),
            "u": UInt32(kVK_ANSI_U), "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
        ]
        guard let keyCode = keyCodes[scalar] else { return nil }
        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "control", "ctrl": modifiers |= UInt32(controlKey)
            case "shift": modifiers |= UInt32(shiftKey)
            case "command", "cmd": modifiers |= UInt32(cmdKey)
            case "option", "alt": modifiers |= UInt32(optionKey)
            default: return nil
            }
        }
        return modifiers == 0 ? nil : HyperliteShortcut(keyCode: keyCode, modifiers: modifiers)
    }
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { ($0 << 8) | OSType($1) }
}
