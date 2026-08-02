import Foundation
import NaturalLanguage

actor HyperliteNoteSearchIndex {
    nonisolated static let maximumResults = 10
    nonisolated static let minimumSemanticScore = 0.45

    typealias VectorProvider = @Sendable (String) -> [Double]?

    private struct Chunk {
        let text: String
        let vector: [Double]?
    }

    private struct IndexedNote {
        let document: HyperliteNoteDocument
        let literalText: String
        let chunks: [Chunk]
    }

    private let embedding: NLEmbedding?
    private let vectorProvider: VectorProvider?
    private var notes: [HyperliteNoteID: IndexedNote] = [:]
    private(set) var isReady = false

    init(vectorProvider: VectorProvider? = nil) {
        self.vectorProvider = vectorProvider
        embedding = vectorProvider == nil ? NLEmbedding.sentenceEmbedding(for: .english) : nil
    }

    func replace(with documents: [HyperliteNoteDocument]) {
        var replacement: [HyperliteNoteID: IndexedNote] = [:]
        for document in documents where document.kind == .pinned || document.exists {
            guard !Task.isCancelled else { return }
            replacement[document.id] = makeIndexedNote(document)
        }
        notes = replacement
        isReady = true
    }

    @discardableResult
    func upsert(_ document: HyperliteNoteDocument) -> Bool {
        if document.kind == .daily, !document.exists {
            return notes.removeValue(forKey: document.id) != nil
        }
        if notes[document.id]?.document == document { return false }
        notes[document.id] = makeIndexedNote(document)
        return true
    }

    func recentDailyNotes(limit: Int = maximumResults) -> [HyperliteRecentDailyNote] {
        notes.values.compactMap { note -> HyperliteRecentDailyNote? in
            guard note.document.kind == .daily,
                  note.document.exists,
                  let date = note.document.date,
                  let updatedAt = note.document.updatedAt
            else { return nil }
            return HyperliteRecentDailyNote(date: date, updatedAt: updatedAt)
        }
        .sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.date > $1.date
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    func search(_ rawQuery: String, limit: Int = maximumResults) -> [HyperliteNoteSearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }
        let normalizedQuery = query.lowercased()
        let queryVector = vector(for: query)
        var results: [HyperliteNoteSearchResult] = []

        for note in notes.values {
            guard !Task.isCancelled else { return [] }
            if note.literalText.contains(normalizedQuery) {
                results.append(result(
                    note: note,
                    snippet: exactSnippet(in: note.document.content, query: query),
                    kind: .exact,
                    score: 2 + exactMetadataScore(note.document, query: normalizedQuery)
                ))
                continue
            }
            guard let queryVector else { continue }
            let best = note.chunks.compactMap { chunk -> (String, Double)? in
                guard let vector = chunk.vector else { return nil }
                return (chunk.text, cosineSimilarity(queryVector, vector))
            }.max { $0.1 < $1.1 }
            guard let best, best.1 >= Self.minimumSemanticScore else { continue }
            results.append(result(
                note: note,
                snippet: displaySnippet(best.0),
                kind: .semantic,
                score: best.1
            ))
        }

        let exactResults = results.filter { $0.matchKind == .exact }
        let candidates = exactResults.isEmpty ? results : exactResults
        return candidates.sorted {
            if $0.matchKind != $1.matchKind { return $0.matchKind == .exact }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.filename > $1.filename
        }
        .prefix(limit)
        .map { $0 }
    }

    private func makeIndexedNote(_ document: HyperliteNoteDocument) -> IndexedNote {
        let metadata = [
            document.kind == .pinned ? "Pinned" : "Daily",
            document.filename,
            document.date ?? "",
        ].joined(separator: "\n")
        let sourceChunks = chunks(for: metadata + "\n" + document.content)
        return IndexedNote(
            document: document,
            literalText: (metadata + "\n" + document.content).lowercased(),
            chunks: sourceChunks.map { Chunk(text: $0, vector: vector(for: $0)) }
        )
    }

    private func vector(for text: String) -> [Double]? {
        vectorProvider?(text) ?? embedding?.vector(for: text)
    }

    private func chunks(for text: String, maximumLength: Int = 800) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var result: [String] = []
        for paragraph in paragraphs {
            let normalized = paragraph
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !normalized.isEmpty else { continue }
            var start = normalized.startIndex
            while start < normalized.endIndex {
                let end = normalized.index(start, offsetBy: maximumLength, limitedBy: normalized.endIndex)
                    ?? normalized.endIndex
                result.append(String(normalized[start ..< end]))
                start = end
            }
        }
        return result
    }

    private func result(
        note: IndexedNote,
        snippet: String,
        kind: HyperliteNoteSearchResult.MatchKind,
        score: Double
    ) -> HyperliteNoteSearchResult {
        HyperliteNoteSearchResult(
            noteID: note.document.id,
            filename: note.document.filename,
            date: note.document.date,
            snippet: snippet,
            matchKind: kind,
            score: score
        )
    }

    private func exactMetadataScore(_ document: HyperliteNoteDocument, query: String) -> Double {
        if document.filename.lowercased().contains(query) { return 0.2 }
        if document.date?.contains(query) == true { return 0.1 }
        return 0
    }

    private func exactSnippet(in content: String, query: String) -> String {
        guard !content.isEmpty else { return "Markdown note" }
        let line = content.components(separatedBy: .newlines).first {
            $0.localizedCaseInsensitiveContains(query)
        }
        return displaySnippet(line ?? content)
    }

    private func displaySnippet(_ value: String, limit: Int = 160) -> String {
        let normalized = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit - 1)) + "…"
    }

    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return -1 }
        var dot = 0.0, leftMagnitude = 0.0, rightMagnitude = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            leftMagnitude += lhs[index] * lhs[index]
            rightMagnitude += rhs[index] * rhs[index]
        }
        guard leftMagnitude > 0, rightMagnitude > 0 else { return -1 }
        return dot / (leftMagnitude.squareRoot() * rightMagnitude.squareRoot())
    }
}
