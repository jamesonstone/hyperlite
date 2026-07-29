import AppKit
import SwiftUI

struct HyperliteThreadDetail: View {
    let thread: HyperliteThread
    let onSeen: () -> Void
    let onSaveNote: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note: String

    init(thread: HyperliteThread, onSeen: @escaping () -> Void, onSaveNote: @escaping (String) -> Void) {
        self.thread = thread
        self.onSeen = onSeen
        self.onSaveNote = onSaveNote
        _note = State(initialValue: thread.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.title).font(.title2.bold())
                    Label(thread.phase.label, systemImage: thread.phase.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailSection("Goal", thread.goal)
                    if let attention = currentAttention {
                        detailSection("Needs your attention", attention.summary)
                        optionalDetailSection("What to do", attention.action)
                        detailSection("Why now", attention.why)
                        optionalDetailSection("If ignored", attention.consequence)
                        optionalDetailSection("Valid while", attention.validWhile)
                    } else {
                        detailSection("Current context", thread.whyNow)
                    }
                    detailSection("Rationale", thread.rationale)
                    detailSection("Progress", progressSummary)
                    if !thread.dependencies.isEmpty {
                        bulletSection("Dependencies and order", thread.dependencies.map {
                            "\($0.kind.replacingOccurrences(of: "_", with: " ")): \($0.targetThreadID ?? $0.target) [\($0.basis)]"
                        })
                    }
                    if !thread.implications.isEmpty {
                        bulletSection("Implications", thread.implications.map {
                            "\($0.summary) [\($0.basis)]"
                        })
                    }
                    bulletSection(
                        "Remaining obligations",
                        thread.remainingObligations.map(\.summary),
                        empty: "No remaining obligation is established by current evidence."
                    )
                    evidenceSection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note").font(.headline)
                        TextEditor(text: $note)
                            .font(.body)
                            .frame(minHeight: 72)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.secondary.opacity(0.25))
                            }
                        HStack {
                            Text("Optional annotation; it never creates or completes a thread.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Save Note") { onSaveNote(note) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 620)
        .onAppear(perform: onSeen)
    }

    private var progressSummary: String {
        let artifactSummary = thread.artifacts.map {
            "\($0.kind.replacingOccurrences(of: "_", with: " ")) \($0.state)"
        }.joined(separator: ", ")
        return artifactSummary.isEmpty ? "No active artifact evidence." : artifactSummary
    }

    private var currentAttention: HyperliteAttentionMoment? {
        thread.attention.last { !$0.seen }
    }

    @ViewBuilder
    private func detailSection(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func optionalDetailSection(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            detailSection(title, value)
        }
    }

    @ViewBuilder
    private func bulletSection(_ title: String, _ values: [String], empty: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if values.isEmpty, let empty {
                Text(empty).foregroundStyle(.secondary)
            } else {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text("• \(value)").textSelection(.enabled)
                }
            }
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Evidence").font(.headline)
            if thread.evidence.isEmpty {
                Text("No evidence is currently cited for this thread.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(thread.evidence) { evidence in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(evidence.title).font(.subheadline.weight(.semibold))
                            Text("\(evidence.source) · \(evidence.freshness)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let value = evidence.url, let url = URL(string: value) {
                            Link("Open", destination: url)
                        } else if let path = evidence.path {
                            Button("Copy Path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            }
                        }
                    }
                }
            }
        }
    }
}
