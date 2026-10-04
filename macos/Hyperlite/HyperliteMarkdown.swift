import SwiftUI

/// One block of a pull request description.
enum HyperliteMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(marker: String, depth: Int, text: String)
    case quote(String)
    case code(String)
    case rule
}

/// A small block parser for PR descriptions: headings, paragraphs, bulleted,
/// numbered, and task lists, quotes, fenced code, and rules. Inline Markdown
/// (emphasis, code, links) is rendered by AttributedString per block.
enum HyperliteMarkdownParser {
    static func blocks(_ markdown: String) -> [HyperliteMarkdownBlock] {
        var blocks: [HyperliteMarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        var fence = ""
        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            // Backtick or tilde fences. An opener may carry an info string; a
            // block closes only on a bare fence of the same character at least
            // as long as its opener.
            if let marker = fenceMarker(trimmed),
               code == nil || (marker.first == fence.first && marker.count >= fence.count && trimmed == marker) {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                    fence = marker
                }
                continue
            }
            if code != nil { code?.append(rawLine); continue }
            if trimmed.isEmpty { flushParagraph(); continue }
            if let heading = heading(trimmed) { flushParagraph(); blocks.append(heading); continue }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { flushParagraph(); blocks.append(.rule); continue }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if let item = listItem(rawLine) { flushParagraph(); blocks.append(item); continue }
            paragraph.append(trimmed)
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }

    private static func fenceMarker(_ line: String) -> String? {
        for char in ["`", "~"] as [Character] {
            let run = line.prefix { $0 == char }
            if run.count >= 3 { return String(run) }
        }
        return nil
    }

    private static func heading(_ line: String) -> HyperliteMarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: line.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String) -> HyperliteMarkdownBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let body = line.trimmingCharacters(in: .whitespaces)
        let depth = min(indent / 2, 3)
        for bullet in ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] "] where body.hasPrefix(bullet) {
            let checked = bullet.contains("x") || bullet.contains("X")
            return .listItem(marker: checked ? "☑" : "☐", depth: depth, text: String(body.dropFirst(bullet.count)))
        }
        for bullet in ["- ", "* ", "+ "] where body.hasPrefix(bullet) {
            return .listItem(marker: "•", depth: depth, text: String(body.dropFirst(2)))
        }
        // Ordered items: up to nine digits followed by "." or ")".
        let digits = body.prefix { $0.isNumber }
        let rest = body.dropFirst(digits.count)
        if !digits.isEmpty, digits.count <= 9, rest.hasPrefix(". ") || rest.hasPrefix(") ") {
            return .listItem(marker: "\(digits)\(rest.prefix(1))", depth: depth, text: String(rest.dropFirst(2)))
        }
        return nil
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// Renders a PR description in the hover card's type scale.
struct HyperliteMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(HyperliteMarkdownParser.blocks(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .foregroundStyle(HyperliteTheme.secondaryText.color)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func view(for block: HyperliteMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(HyperliteMarkdownParser.inline(text))
                .font(level <= 2 ? HyperliteTypography.heading : HyperliteTypography.semibold(HyperliteAppearance.shared.compactSize + 1))
                .foregroundStyle(HyperliteTheme.primaryText.color)
                .padding(.top, 2)
        case let .paragraph(text):
            Text(HyperliteMarkdownParser.inline(text)).font(HyperliteTypography.compact)
        case let .listItem(marker, depth, text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(HyperliteTheme.mutedText.color)
                Text(HyperliteMarkdownParser.inline(text))
            }
            .font(HyperliteTypography.compact)
            .padding(.leading, CGFloat(depth) * 14)
        case let .quote(text):
            Text(HyperliteMarkdownParser.inline(text))
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Rectangle().fill(HyperliteTheme.mutedText.color.opacity(0.4)).frame(width: 2)
                }
        case let .code(text):
            Text(text)
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.primaryText.color)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HyperliteTheme.surface.color, in: RoundedRectangle(cornerRadius: 4))
        case .rule:
            Rectangle().fill(HyperliteTheme.mutedText.color.opacity(0.28)).frame(height: 1)
        }
    }
}
