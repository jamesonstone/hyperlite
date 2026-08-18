import SwiftUI

struct HyperliteAgentSessionDetail: View {
    let session: HyperliteAgentSession
    @ObservedObject var state: HyperliteAgentSessionState
    var onInteraction: () -> Void = {}
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var answer = ""
    @State private var answerIdentity: HyperliteAgentActionIdentity?
    @FocusState private var answerFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let action = session.action { actionCard(action) }
                if !session.messages.isEmpty { messageHistory }
                if let result = session.latestResult, !result.isEmpty {
                    contentCard(title: "Latest Result", text: result)
                }
                routing
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { answerIdentity = session.actionIdentity }
        .onChange(of: session.actionIdentity) { identity in
            if HyperliteAgentAnswerResetPolicy.shouldReset(from: answerIdentity, to: identity) {
                answer = ""
                answerFocused = false
            }
            answerIdentity = identity
        }
        .onChange(of: answerFocused) { focused in onEditingChanged(focused) }
        .onDisappear { onEditingChanged(false) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Label(session.phase.label, systemImage: session.phase.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(session.needsAttention ? Color.orange : Color.secondary)
            }
            Text("\(session.profile) · \(session.project) · revision \(session.revision)")
                .font(HyperliteTypography.regular(10))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func actionCard(_ action: HyperliteAgentPendingAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                action.title,
                systemImage: action.kind == "question" ? "questionmark.bubble" : "exclamationmark.shield"
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.orange)
            Text(action.context)
                .font(HyperliteTypography.regular(11))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let arguments = action.arguments, !arguments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(arguments.keys.sorted(), id: \.self) { key in
                        Text("\(key): \(arguments[key] ?? "")")
                            .font(HyperliteTypography.regular(10))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            actionControls(action)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.55), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func actionControls(_ action: HyperliteAgentPendingAction) -> some View {
        let submitting = state.isSubmitting(session)
        if action.canAnswer {
            HStack(alignment: .center, spacing: 8) {
                TextField("Answer", text: $answer)
                    .textFieldStyle(.roundedBorder)
                    .focused($answerFocused)
                    .onSubmit(submitAnswer)
                if submitting { ProgressView().controlSize(.small) }
                Button("Answer", action: submitAnswer)
                    .buttonStyle(.borderedProminent)
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
            }
        } else {
            HStack(spacing: 8) {
                if action.canAllowOnce {
                    Button("Allow Once") {
                        onInteraction()
                        state.submit("allow_once", for: session)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if action.canDeny {
                    Button("Deny", role: .destructive) {
                        onInteraction()
                        state.submit("deny", for: session)
                    }
                    .buttonStyle(.bordered)
                }
                if submitting { ProgressView().controlSize(.small) }
            }
            .disabled(submitting)
        }
    }

    private func submitAnswer() {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !state.isSubmitting(session) else { return }
        onInteraction()
        state.submit("answer", for: session, answers: ["answer": [trimmed]])
    }

    private var messageHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Messages").font(.system(size: 12, weight: .semibold))
            ForEach(Array(session.messages.enumerated()), id: \.offset) { _, message in
                VStack(alignment: .leading, spacing: 3) {
                    Text(message.role == "user" ? "You" : "Agent")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(message.text)
                        .font(HyperliteTypography.regular(11))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func contentCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(HyperliteTypography.regular(11))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var routing: some View {
        HStack(spacing: 8) {
            if let path = session.routing.workspacePath, !path.isEmpty {
                Text(path)
                    .font(HyperliteTypography.regular(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if let destination = session.routeDestination {
                Button(destination.label) {
                    onInteraction()
                    state.performRoute(session)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
