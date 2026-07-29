import SwiftUI

struct HyperliteProjectMap: View {
    let projects: [HyperliteProjectLocation]

    private let columns = [
        GridItem(.flexible(), spacing: 24, alignment: .top),
        GridItem(.flexible(), spacing: 24, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Projects")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(projects.count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Configured paths")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(projects) { project in
                    HyperliteProjectMapEntry(project: project)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Configured project paths")
    }
}

private struct HyperliteProjectMapEntry: View {
    let project: HyperliteProjectLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(project.lanes.enumerated()), id: \.element.id) { index, lane in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(index == 0 ? project.name : "")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(width: 68, alignment: .leading)
                    Text(HyperliteProjectIndexPresentation.laneLabel(lane))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(width: 64, alignment: .leading)
                    Text(HyperliteProjectIndexPresentation.abbreviatedPath(lane.path))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .help(lane.path)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(project.name), \(HyperliteProjectIndexPresentation.laneLabel(lane)), \(lane.path)"
                )
            }
        }
        .padding(.vertical, 2)
    }
}
