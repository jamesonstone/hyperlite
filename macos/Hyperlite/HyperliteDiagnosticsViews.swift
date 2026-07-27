import SwiftUI

struct HyperliteDiagnosticsButton: View {
    let errors: [HyperliteDiagnostic]
    let warnings: [HyperliteDiagnostic]
    let isPruning: Bool
    let clickRequest: Int
    let onPruneRequest: (HyperliteDiagnostic) -> Void

    @State private var presentation = Presentation.hidden
    @State private var triggerHovered = false
    @State private var popoverHovered = false
    @State private var pendingTask: Task<Void, Never>?

    private enum Presentation: Equatable {
        case hidden
        case hover
        case interactive
    }

    private var diagnostics: [PresentedDiagnostic] {
        errors.map { PresentedDiagnostic(diagnostic: $0, isError: true) } +
            warnings.map { PresentedDiagnostic(diagnostic: $0, isError: false) }
    }

    var body: some View {
        Button(action: presentInteractively) {
            HStack(spacing: 4) {
                Image(systemName: errors.isEmpty ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                Text("\(diagnostics.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
            }
        }
        .buttonStyle(.bordered)
        .foregroundStyle(errors.isEmpty ? .orange : .red)
        .help(HyperliteInteractionModel.diagnosticCountSummary(
            errors: errors.count,
            warnings: warnings.count
        ))
        .accessibilityLabel("Scan diagnostics")
        .onHover { hovered in
            triggerHovered = hovered
            hovered ? scheduleOpen() : scheduleClose()
        }
        .popover(isPresented: isPresented, arrowEdge: .top) {
            diagnosticsPopover
        }
        .onChange(of: clickRequest) { _ in presentInteractively() }
        .onDisappear {
            pendingTask?.cancel()
            pendingTask = nil
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { presentation != .hidden },
            set: { if !$0 { presentation = .hidden } }
        )
    }

    private var diagnosticsPopover: some View {
        let height = min(CGFloat(360), max(CGFloat(120), CGFloat(diagnostics.count * 72 + 54)))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scan Diagnostics")
                    .font(.headline)
                Spacer()
                Text(HyperliteInteractionModel.diagnosticCountSummary(
                    errors: errors.count,
                    warnings: warnings.count
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(diagnostics) { item in
                        diagnosticRow(item)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 450, height: height)
        .onHover { hovered in
            popoverHovered = hovered
            hovered ? pendingTask?.cancel() : scheduleClose()
        }
        .onExitCommand { presentation = .hidden }
    }

    private func diagnosticRow(_ item: PresentedDiagnostic) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(item.isError ? .red : .orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(item.diagnostic.repository) · \(item.diagnostic.stage)")
                    .font(.subheadline.weight(.semibold))
                Text(HyperliteInteractionModel.truncated(item.diagnostic.message, limit: 300))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            Spacer(minLength: 8)
            if presentation == .interactive, item.diagnostic.isPrunableWorktree {
                Button("Prune") {
                    presentation = .hidden
                    onPruneRequest(item.diagnostic)
                }
                .buttonStyle(.bordered)
                .disabled(isPruning)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }

    private func presentInteractively() {
        pendingTask?.cancel()
        presentation = .interactive
    }

    private func scheduleOpen() {
        pendingTask?.cancel()
        guard presentation == .hidden else { return }
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, triggerHovered, presentation == .hidden else { return }
            presentation = .hover
        }
    }

    private func scheduleClose() {
        pendingTask?.cancel()
        guard presentation == .hover else { return }
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, !triggerHovered, !popoverHovered,
                  presentation == .hover else { return }
            presentation = .hidden
        }
    }
}

private struct PresentedDiagnostic: Identifiable {
    let diagnostic: HyperliteDiagnostic
    let isError: Bool

    var id: String {
        "\(isError ? "error" : "warning"):\(diagnostic.id)"
    }
}
