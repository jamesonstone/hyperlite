import Foundation

enum HyperliteNotepadTests {
    @MainActor
    static func run() async throws {
        expect(
            HyperliteNotepadState.autosaveDelay == .seconds(3),
            "production autosave should wait for three idle seconds"
        )
        let client = NotepadClient(initial: "Persisted context\n")
        let state = HyperliteNotepadState(
            client: client,
            autosaveDelay: .milliseconds(20)
        )
        await state.waitUntilLoaded()
        expect(state.text == "Persisted context\n", "notepad should load persisted content")

        expect(state.update("first"), "first edit should be accepted")
        expect(state.update("second"), "second edit should be accepted")
        try? await Task.sleep(for: .milliseconds(60))
        _ = await state.flush()
        let autosaved = await client.savedValues()
        expect(autosaved == ["second"], "autosave should persist only the latest edit")
        expect(!state.isDirty, "successful autosave should clear the dirty state")

        expect(state.update("flush before debounce"), "flush edit should be accepted")
        let didFlush = await state.flush()
        expect(didFlush, "explicit flush should persist pending content")
        let flushed = await client.savedValues()
        expect(
            flushed == ["second", "flush before debounce"],
            "flush should not wait for the debounce"
        )

        let previous = state.text
        let oversized = String(repeating: "x", count: HyperliteNotepadState.maxBytes + 1)
        expect(!state.update(oversized), "oversized edits should be rejected")
        expect(state.text == previous, "rejected content should not replace the draft")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}

private actor NotepadClient: HyperliteNotepadClient {
    private let initial: String
    private var saves: [String] = []

    init(initial: String) {
        self.initial = initial
    }

    func load() async throws -> String {
        initial
    }

    func save(_ content: String) async throws {
        saves.append(content)
    }

    func savedValues() -> [String] {
        saves
    }
}
