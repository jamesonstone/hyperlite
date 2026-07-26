import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI

private let defaultHotKey = "Control+Shift+H"

private func openHyperliteSettings() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}

@main
struct HyperliteApp: App {
    @NSApplicationDelegateAdaptor(HyperliteApplicationDelegate.self) private var applicationDelegate
    @StateObject private var state = HyperliteState.shared

    var body: some Scene {
        WindowGroup("Hyperlite", id: "hyperlite") {
            HyperliteWindow(state: state)
        }
        .defaultSize(width: 480, height: 650)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            HyperliteMenu(state: state)
        } label: {
            HyperliteMenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            HyperliteSettingsView()
        }
    }
}

@MainActor
final class HyperliteApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var hotKey: HyperliteHotKeyController?
    private weak var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = HyperliteHotKeyController { [weak self] in
            HyperliteState.shared.refresh()
            self?.showWindow()
        }
        hotKey?.start()
        DispatchQueue.main.async { [weak self] in
            self?.window = NSApp.windows.first(where: { $0.title == "Hyperlite" })
            self?.window?.delegate = self
            self?.showWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let target = window ?? NSApp.windows.first(where: { $0.title == "Hyperlite" })
        target?.makeKeyAndOrderFront(nil)
    }
}

final class HyperliteHotKeyController {
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

@MainActor
final class HyperliteState: ObservableObject {
    static let shared = HyperliteState()

    @Published private(set) var scan: HyperliteWorkScan?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    private var refreshTask: Task<Void, Never>?

    init() { refresh(localOnly: true) }

    deinit { refreshTask?.cancel() }

    func refresh() { refresh(localOnly: false) }

    func items(maxAgeDays: Int, now: Date = Date()) -> [HyperliteWorkItem] {
        guard let scan else { return [] }
        return HyperlitePresentation.items(scan: scan, maxAgeDays: maxAgeDays, now: now)
    }

    func attentionProjectCount(maxAgeDays: Int, now: Date = Date()) -> Int {
        Set(items(maxAgeDays: maxAgeDays, now: now).map(\.repositoryPath)).count
    }

    private func refresh(localOnly: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let arguments = localOnly ? ["--json", "--local", "--no-refresh"] : ["--json"]
                let data = try await Self.runHyperlite(arguments: arguments)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .custom { decoder in
                    let value = try decoder.singleValueContainer().decode(String.self)
                    let fractionalSecondsFormatter = ISO8601DateFormatter()
                    fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = fractionalSecondsFormatter.date(from: value) { return date }
                    let internetDateTimeFormatter = ISO8601DateFormatter()
                    internetDateTimeFormatter.formatOptions = [.withInternetDateTime]
                    if let date = internetDateTimeFormatter.date(from: value) { return date }
                    let container = try decoder.singleValueContainer()
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid ISO-8601 date")
                }
                scan = try decoder.decode(HyperliteWorkScan.self, from: data)
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    private static func runHyperlite(arguments: [String]) async throws -> Data {
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/hyperlite-cli")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw HyperliteError.helperMissing }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0 else {
                    let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: HyperliteError.scanFailed(message ?? "hyperlite exited with status \(process.terminationStatus)"))
                    return
                }
                continuation.resume(returning: data)
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

private enum HyperliteError: LocalizedError {
    case helperMissing
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing: "Hyperlite's scan helper is unavailable"
        case let .scanFailed(message): "Hyperlite scan failed: \(message)"
        }
    }
}

private struct HyperliteMenuBarLabel: View {
    @ObservedObject var state: HyperliteState
    @AppStorage("hyperlite.max-age-days") private var maxAgeDays = 10
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey

    var body: some View {
        let count = state.attentionProjectCount(maxAgeDays: maxAgeDays)
        HStack(spacing: 2) {
            Text("🚀")
            Text("✦ \(count > 99 ? "99+" : "\(count)")")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .help("Hyperlite — \(count) project\(count == 1 ? "" : "s") need attention — \(hotkey)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hyperlite, \(count) projects need attention")
    }
}

private struct HyperliteMenu: View {
    @ObservedObject var state: HyperliteState

    var body: some View {
        Button("Open Hyperlite") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.title == "Hyperlite" })?.makeKeyAndOrderFront(nil)
        }
        Button("Refresh") { state.refresh() }
        Divider()
        Button("Settings…") { openHyperliteSettings() }
        Button("Quit Hyperlite") { NSApp.terminate(nil) }
    }
}

struct HyperliteWindow: View {
    @ObservedObject var state: HyperliteState
    @AppStorage("hyperlite.max-age-days") private var maxAgeDays = 10

    private var visibleItems: [HyperliteWorkItem] { state.items(maxAgeDays: maxAgeDays) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hyperlite").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("🚀 \(state.attentionProjectCount(maxAgeDays: maxAgeDays)) active project\(state.attentionProjectCount(maxAgeDays: maxAgeDays) == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered)
                    .disabled(state.isRefreshing)
                    .help("Refresh Git and pull request status")
                Button(action: openHyperliteSettings) { Image(systemName: "gearshape.fill") }
                    .buttonStyle(.bordered)
                    .help("Hyperlite settings")
            }

            if let errorMessage = state.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if state.scan == nil {
                ProgressView("Checking local work…")
                    .controlSize(.small)
            } else if let scan = state.scan {
                if !scan.errors.isEmpty || !scan.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(partialScanSummary(for: scan), systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(scan.errors.isEmpty ? .orange : .red)
                        ForEach(scan.errors.indices, id: \.self) { index in
                            Text("Error: \(diagnosticDescription(scan.errors[index]))")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        ForEach(scan.warnings.indices, id: \.self) { index in
                            Text("Warning: \(diagnosticDescription(scan.warnings[index]))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if visibleItems.isEmpty {
                    HyperliteEmptyState()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(visibleItems) { item in
                                HyperliteRow(item: item)
                                if item.id != visibleItems.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 560)
    }

    private func partialScanSummary(for scan: HyperliteWorkScan) -> String {
        var diagnostics: [String] = []
        if !scan.errors.isEmpty {
            diagnostics.append("\(scan.errors.count) error\(scan.errors.count == 1 ? "" : "s")")
        }
        if !scan.warnings.isEmpty {
            diagnostics.append("\(scan.warnings.count) warning\(scan.warnings.count == 1 ? "" : "s")")
        }
        return "Partial scan: \(diagnostics.joined(separator: " and ")). Results may be incomplete."
    }

    private func diagnosticDescription(_ diagnostic: HyperliteDiagnostic) -> String {
        "\(diagnostic.repository) (\(diagnostic.stage)): \(diagnostic.message)"
    }
}

private struct HyperliteEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Nothing needs attention")
                .font(.headline)
            Text("No recent worktrees, main-branch changes, or pull requests.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct HyperliteSettingsView: View {
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey
    @AppStorage("hyperlite.max-age-days") private var maxAgeDays = 10

    var body: some View {
        Form {
            Section("Display") {
                Picker("Show recent work", selection: $maxAgeDays) {
                    ForEach(HyperlitePresentation.supportedAgeWindows, id: \.self) { days in
                        Text("Last \(days) days").tag(days)
                    }
                }
            }
            Section("Shortcut") {
                TextField("Hot key", text: $hotkey)
                Text("Default: \(defaultHotKey). Use modifier names joined with +, for example Command+Shift+H.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Quit Hyperlite") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
    }
}

private struct HyperliteRow: View {
    let item: HyperliteWorkItem

    var body: some View {
        Button(action: activate) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.statuses.first?.symbol ?? "circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(color(for: item.statuses.first))
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.repository).font(.system(size: 16, weight: .bold))
                        Spacer(minLength: 8)
                        Text(HyperlitePresentation.ageLabel(for: item.updatedAt))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    HStack(spacing: 7) {
                        ForEach(item.statuses, id: \.self) { status in
                            Label(status.label, systemImage: status.symbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(color(for: status))
                        }
                    }
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(description)
    }

    private var description: String {
        let status = item.statuses.map(\.label).joined(separator: ", ")
        if item.pullRequest != nil { return "\(status). Click to open the pull request in your browser." }
        return "\(status). Click to copy \(item.clickPath)."
    }

    private func activate() {
        if let urlString = item.pullRequest?.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.clickPath, forType: .string)
    }

    private func color(for status: HyperliteStatus?) -> Color {
        switch status {
        case .pullRequest: .pink
        case .worktree: .cyan
        case .unstaged: .red
        case nil: .secondary
        }
    }
}
