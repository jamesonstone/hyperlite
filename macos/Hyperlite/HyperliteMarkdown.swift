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
        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
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
        let digits = body.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count < 4, body.dropFirst(digits.count).hasPrefix(". ") {
            return .listItem(marker: "\(digits).", depth: depth, text: String(body.dropFirst(digits.count + 2)))
        }
        return nil
    }

    static func inline(_ text: String) -> AttributedString {
        let text = HyperliteEmoji.render(text)
        return (try? AttributedString(
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
