import Foundation

enum HyperlitePinboardGeometry {
    static let sectionHeaderHeight = 36.0
    static let minimumSectionWidth = 260.0
    static let minimumSectionHeight = 300.0
    static let maximumSectionWidth = 700.0
    static let maximumSectionHeight = 950.0
    static let noteWidth = 220.0
    static let noteHeight = 150.0

    static func movedSection(
        _ frame: HyperlitePinboardFrame,
        translationX: Double,
        translationY: Double,
        board: HyperlitePinboardSize
    ) -> HyperlitePinboardFrame {
        clampSection(
            HyperlitePinboardFrame(
                x: frame.x + translationX,
                y: frame.y + translationY,
                width: frame.width,
                height: frame.height
            ),
            board: board
        )
    }

    static func resizedSection(
        _ frame: HyperlitePinboardFrame,
        translationX: Double,
        translationY: Double,
        board: HyperlitePinboardSize
    ) -> HyperlitePinboardFrame {
        clampSection(
            HyperlitePinboardFrame(
                x: frame.x,
                y: frame.y,
                width: frame.width + translationX,
                height: frame.height + translationY
            ),
            board: board
        )
    }

    static func noteDestination(
        layout: HyperlitePinboardNoteLayout,
        translationX: Double,
        translationY: Double,
        sections: [HyperlitePinboardSection]
    ) -> HyperlitePinboardNoteLayout? {
        guard let source = sections.first(where: { $0.id == layout.sectionID }) else { return nil }
        let globalX = source.frame.x + layout.frame.x + translationX
        let globalY = source.frame.y + sectionHeaderHeight + layout.frame.y + translationY
        let centerX = globalX + noteWidth / 2
        let centerY = globalY + noteHeight / 2
        let target = sections.reversed().first { section in
            centerX >= section.frame.x && centerX <= section.frame.x + section.frame.width &&
                centerY >= section.frame.y + sectionHeaderHeight &&
                centerY <= section.frame.y + section.frame.height
        } ?? source
        let proposed = HyperlitePinboardFrame(
            x: globalX - target.frame.x,
            y: globalY - target.frame.y - sectionHeaderHeight,
            width: noteWidth,
            height: noteHeight
        )
        return HyperlitePinboardNoteLayout(
            noteID: layout.noteID,
            sectionID: target.id,
            frame: clampNote(proposed, section: target.frame)
        )
    }

    static func clampNote(
        _ frame: HyperlitePinboardFrame,
        section: HyperlitePinboardFrame
    ) -> HyperlitePinboardFrame {
        HyperlitePinboardFrame(
            x: min(max(frame.x.isFinite ? frame.x : 0, 0), max(section.width - noteWidth, 0)),
            y: min(
                max(frame.y.isFinite ? frame.y : 0, 0),
                max(section.height - sectionHeaderHeight - noteHeight, 0)
            ),
            width: noteWidth,
            height: noteHeight
        )
    }

    private static func clampSection(
        _ frame: HyperlitePinboardFrame,
        board: HyperlitePinboardSize
    ) -> HyperlitePinboardFrame {
        let width = min(max(frame.width, minimumSectionWidth), min(maximumSectionWidth, board.width))
        let height = min(max(frame.height, minimumSectionHeight), min(maximumSectionHeight, board.height))
        return HyperlitePinboardFrame(
            x: min(max(frame.x, 0), max(board.width - width, 0)),
            y: min(max(frame.y, 0), max(board.height - height, 0)),
            width: width,
            height: height
        )
    }
}
