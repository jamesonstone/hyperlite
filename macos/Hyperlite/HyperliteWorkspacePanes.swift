import SwiftUI

struct HyperliteWorkspacePanes<PullRequests: View, Notepad: View>: View {
    let verticalMode: Bool
    let pullRequests: PullRequests
    let notepad: Notepad

    init(
        verticalMode: Bool,
        @ViewBuilder pullRequests: () -> PullRequests,
        @ViewBuilder notepad: () -> Notepad
    ) {
        self.verticalMode = verticalMode
        self.pullRequests = pullRequests()
        self.notepad = notepad()
    }

    var body: some View {
        let spacing = HyperliteWorkspaceSizing.sectionSpacing
        if verticalMode {
            HStack(alignment: .top, spacing: spacing) {
                pullRequests
                notepad
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                pullRequests
                notepad
            }
        }
    }
}
