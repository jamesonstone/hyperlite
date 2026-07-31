import SwiftUI

struct HyperliteProjectMap: View {
    let projects: [HyperliteProjectLocation]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Projects")
                    .font(HyperliteTypography.semibold(11))
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
                Text("\(projects.count)")
                    .font(HyperliteTypography.bold(10).monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                Spacer()
                Text("Active branches and worktrees")
                    .font(HyperliteTypography.regular(10))
                    .foregroundStyle(HyperliteTheme.mutedText.color)
            }

            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(projects) { project in
                    HyperliteProjectMapEntry(project: project)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active project branches and worktrees")
    }
}

private struct HyperliteProjectMapEntry: View {
    let project: HyperliteProjectLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(project.lanes.enumerated()), id: \.element.id) { index, lane in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(index == 0 ? project.name : "")
                        .font(HyperliteTypography.medium(10))
                        .foregroundStyle(HyperliteTheme.mutedText.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 190, alignment: .leading)
                    Text(HyperliteProjectIndexPresentation.laneKind(lane))
                        .font(HyperliteTypography.regular(10))
                        .foregroundStyle(HyperliteTheme.mutedText.color)
                        .lineLimit(1)
                        .frame(width: 58, alignment: .leading)
                    Text(HyperliteProjectIndexPresentation.laneLabel(lane))
                        .font(HyperliteTypography.regular(10))
                        .foregroundStyle(HyperliteTheme.mutedText.color)
                        .lineLimit(1)
                        .frame(width: 86, alignment: .leading)
                    Text(HyperliteProjectIndexPresentation.abbreviatedPath(lane.path))
                        .font(HyperliteTypography.regular(10))
                        .foregroundStyle(HyperliteTheme.secondaryText.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .help(lane.path)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(project.name), \(HyperliteProjectIndexPresentation.laneKind(lane)), " +
                        "\(HyperliteProjectIndexPresentation.laneLabel(lane)), \(lane.path)"
                )
            }
        }
        .padding(.vertical, 2)
    }
}
