import Foundation

enum HyperliteEmojiTests {
    static func run() {
        let render = HyperliteEmoji.render
        expect(render(":sparkles: add proposals") == "✨ add proposals", "gitmoji shortcodes render")
        expect(render("fix(GH-1): :bug: x :recycle:") == "fix(GH-1): 🐛 x ♻️", "several shortcodes render")
        expect(render("time 10:30:45 and :not_a_code:") == "time 10:30:45 and :not_a_code:",
               "unknown shortcodes and clock times stay as written")
        expect(render("a :+1: b") == "a 👍 b", "punctuation shortcodes render")
        expect(render(":t-rex: legacy") == "🦖 legacy", "the full gitmoji set includes t-rex")
        expect(render("trailing colon:") == "trailing colon:", "an unmatched colon stays")
        expect(String(HyperliteMarkdownParser.inline(":memo: **docs**").characters) == "📝 docs",
               "description inline text renders emoji")
        expect(HyperliteMarkdownParser.blocks("```\n:bug:\n```") == [.code(":bug:")], "code blocks stay literal")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
