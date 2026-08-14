import Foundation

enum HyperlitePinboardTests {
    @MainActor
    static func run() async throws {
        try testSnapshotDecodingAndMutationEncoding()
        testBoundedSectionGeometry()
        testNoteClampingAndCrossSectionReparenting()
        try await testStateLoadsAndPublishesMutationSnapshots()
    }

    private static func testSnapshotDecodingAndMutationEncoding() throws {
        let data = Data("""
        {
          "board": {
            "schema_version": 1,
            "size": {"width": 1600, "height": 1000},
            "sections": [{
              "id": "11111111111111111111111111111111",
              "title": "Ideas",
              "frame": {"x": 24, "y": 24, "width": 320, "height": 560}
            }],
            "notes": [{
              "note_id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "section_id": "11111111111111111111111111111111",
              "frame": {"x": 18, "y": 18, "width": 220, "height": 150}
            }]
          },
          "notes": [{
            "id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "title": "Spatial note",
            "description": "Plain Markdown-compatible content",
            "created_at": "2026-08-14T12:00:00Z",
            "updated_at": "2026-08-14T12:00:00Z"
          }],
          "archive": []
        }
        """.utf8)
        let snapshot = try HyperliteJSON.decoder.decode(HyperlitePinboardSnapshot.self, from: data)
        expect(snapshot.board.schemaVersion == 1, "pinboard schema should decode")
        expect(snapshot.notesByID["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]?.title == "Spatial note",
               "pinboard notes should index by opaque id")
        expect(snapshot.board.notes[0].sectionID == snapshot.board.sections[0].id,
               "note membership should decode from snake_case")

        let mutation = HyperlitePinboardMutation(
            kind: .moveNote,
            sectionID: snapshot.board.sections[0].id,
            noteID: snapshot.board.notes[0].noteID,
            frame: snapshot.board.notes[0].frame
        )
        let encoded = String(decoding: try JSONEncoder().encode(mutation), as: UTF8.self)
        expect(encoded.contains("\"section_id\""), "mutations should encode section_id")
        expect(encoded.contains("\"note_id\""), "mutations should encode note_id")
        expect(!encoded.contains("sectionID"), "mutations should not leak Swift key casing")
    }

    private static func testBoundedSectionGeometry() {
        let board = HyperlitePinboardSize(width: 1600, height: 1000)
        let source = HyperlitePinboardFrame(x: 24, y: 24, width: 320, height: 560)
        let moved = HyperlitePinboardGeometry.movedSection(
            source,
            translationX: 2000,
            translationY: -100,
            board: board
        )
        expect(moved.x == 1280 && moved.y == 0,
               "section movement should clamp to the finite board")
        let resized = HyperlitePinboardGeometry.resizedSection(
            source,
            translationX: -1000,
            translationY: 1000,
            board: board
        )
        expect(resized.width == 260 && resized.height == 950,
               "section resizing should preserve conservative bounds")
    }

    private static func testNoteClampingAndCrossSectionReparenting() {
        let first = HyperlitePinboardSection(
            id: "11111111111111111111111111111111",
            title: "First",
            frame: HyperlitePinboardFrame(x: 20, y: 20, width: 320, height: 560)
        )
        let second = HyperlitePinboardSection(
            id: "22222222222222222222222222222222",
            title: "Second",
            frame: HyperlitePinboardFrame(x: 400, y: 20, width: 320, height: 560)
        )
        let layout = HyperlitePinboardNoteLayout(
            noteID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            sectionID: first.id,
            frame: HyperlitePinboardFrame(x: 20, y: 20, width: 220, height: 150)
        )
        let destination = HyperlitePinboardGeometry.noteDestination(
            layout: layout,
            translationX: 380,
            translationY: 0,
            sections: [first, second]
        )
        expect(destination?.sectionID == second.id,
               "cross-boundary movement should reparent to the target section")
        expect(destination?.frame.x == 20 && destination?.frame.y == 20,
               "reparenting should translate coordinates into the target section")

        let clamped = HyperlitePinboardGeometry.clampNote(
            HyperlitePinboardFrame(x: -20, y: 900, width: 1, height: 1),
            section: first.frame
        )
        expect(clamped.x == 0 && clamped.y == 374,
               "note movement should clamp inside section content")
        expect(clamped.width == 220 && clamped.height == 150,
               "v1 notes should keep one readable card size")
    }

    @MainActor
    private static func testStateLoadsAndPublishesMutationSnapshots() async throws {
        let section = HyperlitePinboardSection(
            id: "11111111111111111111111111111111",
            title: "Ideas",
            frame: HyperlitePinboardFrame(x: 24, y: 24, width: 320, height: 560)
        )
        let initial = HyperlitePinboardSnapshot(
            board: HyperlitePinboardBoard(
                schemaVersion: 1,
                size: HyperlitePinboardSize(width: 1600, height: 1000),
                sections: [section],
                notes: []
            ),
            notes: [],
            archive: []
        )
        let note = HyperlitePinboardNote(
            id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            title: "Published mutation",
            description: "The helper response is authoritative.",
            createdAt: Date(timeIntervalSince1970: 1_786_714_400),
            updatedAt: Date(timeIntervalSince1970: 1_786_714_400),
            forkedFrom: nil,
            archivedAt: nil,
            archivedFromSectionID: nil,
            archivedFromSectionTitle: nil
        )
        let updated = HyperlitePinboardSnapshot(
            board: HyperlitePinboardBoard(
                schemaVersion: 1,
                size: initial.board.size,
                sections: [section],
                notes: [HyperlitePinboardNoteLayout(
                    noteID: note.id,
                    sectionID: section.id,
                    frame: HyperlitePinboardFrame(x: 18, y: 18, width: 220, height: 150)
                )]
            ),
            notes: [note],
            archive: []
        )
        let client = HyperlitePinboardTestClient(initial: initial, mutationResult: updated)
        let state = HyperlitePinboardState(client: client)
        try await waitForState { state.snapshot == initial }

        let result = await state.apply(HyperlitePinboardMutation(
            kind: .addNote,
            sectionID: section.id,
            title: note.title,
            description: note.description
        ))
        expect(result == updated && state.snapshot == updated,
               "state should publish the complete helper mutation snapshot")
        expect(state.errorMessage == nil && !state.isLoading && !state.isMutating,
               "successful state transitions should settle without an error")
        let observedMutationCount = await client.observedMutationCount()
        expect(observedMutationCount == 1,
               "one state action should issue exactly one typed mutation")
    }

    @MainActor
    private static func waitForState(_ condition: @escaping () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                throw HyperlitePinboardTestError.timedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}

private enum HyperlitePinboardTestError: Error {
    case timedOut
}

private actor HyperlitePinboardTestClient: HyperlitePinboardClient {
    let initial: HyperlitePinboardSnapshot
    let mutationResult: HyperlitePinboardSnapshot
    private var mutationCount = 0

    init(initial: HyperlitePinboardSnapshot, mutationResult: HyperlitePinboardSnapshot) {
        self.initial = initial
        self.mutationResult = mutationResult
    }

    func load() async throws -> HyperlitePinboardSnapshot { initial }

    func mutate(_ mutation: HyperlitePinboardMutation) async throws -> HyperlitePinboardSnapshot {
        mutationCount += 1
        return mutationResult
    }

    func observedMutationCount() -> Int { mutationCount }
}
