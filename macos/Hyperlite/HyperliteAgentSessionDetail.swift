import SwiftUI

struct HyperliteAgentSessionDetail: View {
    let session: HyperliteAgentSession
    @ObservedObject var state: HyperliteAgentSessionState
    @State private var answer = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let action = session.action {
                    actionCard(action)
                }
                if !session.messages.isEmpty {
                    messageHistory
                }
                if let result = session.latestResult, !result.isEmpty {
                    contentCard(title: "Latest result", text: result)
                }
                routing
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(session.displayTitle)
                    .font(HyperliteTypography.semibold(13))
                Spacer()
                Label(session.phase.label, systemImage: session.phase.symbol)
                    .font(HyperliteTypography.medium(9))
                    .foregroundStyle(session.needsAttention ? HyperliteTheme.orange.color : HyperliteTheme.secondaryText.color)
            }
            Text("\(session.profile) · \(session.project) · revision \(session.revision)")
                .font(HyperliteTypography.regular(8))
                .foregroundStyle(HyperliteTheme.mutedText.color)
        }
    }

    private func actionCard(_ action: HyperliteAgentPendingAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(action.title, systemImage: action.kind == "question" ? "questionmark.bubble" : "exclamationmark.shield")
                .font(HyperliteTypography.semibold(11))
                .foregroundStyle(HyperliteTheme.orange.color)
            Text(action.context)
                .font(HyperliteTypography.regular(10))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let arguments = action.arguments, !arguments.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(arguments.keys.sorted(), id: \.self) { key in
                        Text("\(key): \(arguments[key] ?? "")")
                            .font(HyperliteTypography.regular(8))
                            .foregroundStyle(HyperliteTheme.secondaryText.color)
                            .textSelection(.enabled)
                    }
                }
            }
            if action.canAnswer {
                TextField("Answer", text: $answer)
                    .textFieldStyle(.roundedBorder)
                Button("Answer") {
                    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    state.submit("answer", for: session, answers: ["answer": [trimmed]])
                    answer = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                HStack {
                    if action.canAllowOnce {
                        Button("Allow Once") { state.submit("allow_once", for: session) }
                            .buttonStyle(.borderedProminent)
                    }
                    if action.canDeny {
                        Button("Deny") { state.submit("deny", for: session) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(10)
        .background(HyperliteTheme.surface.color)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(HyperliteTheme.orange.color.opacity(0.7)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private var messageHistory: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Recent messages")
                .font(HyperliteTypography.semibold(10))
            ForEach(Array(session.messages.enumerated()), id: \.offset) { _, message in
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.role == "user" ? "You" : "Agent")
                        .font(HyperliteTypography.semibold(8))
                        .foregroundStyle(HyperliteTheme.mutedText.color)
                    Text(message.text)
                        .font(HyperliteTypography.regular(9))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(HyperliteTheme.surface.color)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private func contentCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(HyperliteTypography.semibold(9))
            Text(text)
                .font(HyperliteTypography.regular(9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(HyperliteTheme.surface.color)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var routing: some View {
        HStack {
            if let path = session.routing.workspacePath, !path.isEmpty {
                Text(path)
                    .font(HyperliteTypography.regular(8))
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if session.openInClient {
                Button("Open in client") { state.openInClient(session) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
