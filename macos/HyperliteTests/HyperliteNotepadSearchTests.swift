import Foundation

extension HyperliteNotepadTests {
    static func testSearchIndexExactAndSemantic() async throws {
        let index = HyperliteNoteSearchIndex { text in
            let text = text.lowercased()
            if text.contains("storage") || text.contains("database") || text.contains("postgres") ||
                text == "pinned.md"
            {
                return [1, 0]
            }
            if text.contains("ocean") || text.contains("marine") { return [0, 1] }
            return nil
        }
        let pinned = document(.pinned, content: "Repository paths and stable identifiers")
        let database = document(
            .daily("2026-08-01"),
            content: "Configured the PostgreSQL database pool",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let ocean = document(
            .daily("2026-08-02"),
            content: "Reviewed marine habitat notes",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        await index.replace(with: [pinned, database, ocean])

        let filenameResults = await index.search("pinned.md")
        expect(
            filenameResults.first?.noteID == .pinned && filenameResults.first?.matchKind == .exact,
            "literal filename search should return pinned first"
        )
        expect(filenameResults.count == 1, "literal matches should suppress semantic noise")
        let dateResults = await index.search("2026-08-02")
        expect(
            dateResults.first?.noteID == .daily("2026-08-02"),
            "literal date search should return its daily note"
        )
        let semanticResults = await index.search("storage")
        expect(
            semanticResults.first?.noteID == .daily("2026-08-01") &&
                semanticResults.first?.matchKind == .semantic,
            "semantic search should retrieve related database content"
        )
    }
}
