import Foundation

enum HyperliteMarkdownTests {
    static func run() {
        let blocks = HyperliteMarkdownParser.blocks("""
        ## Description

        After looking up a TRF, events
        stayed absent.

        - one **bold**
          - nested
        1. first
        - [x] done
        > quoted
        ```
        code line
        ```
        ---
        """)
        expect(blocks == [
            .heading(level: 2, text: "Description"),
            .paragraph("After looking up a TRF, events stayed absent."),
            .listItem(marker: "•", depth: 0, text: "one **bold**"),
            .listItem(marker: "•", depth: 1, text: "nested"),
            .listItem(marker: "1.", depth: 0, text: "first"),
            .listItem(marker: "☑", depth: 0, text: "done"),
            .quote("quoted"),
            .code("code line"),
            .rule,
        ], "description blocks parse as written; got \(blocks)")
        expect(String(HyperliteMarkdownParser.inline("a **b** `c`").characters) == "a b c",
               "inline markdown renders without markup characters")
        expect(HyperliteMarkdownParser.blocks("#nospace").first == .paragraph("#nospace"),
               "a hash without a space is not a heading")
        let link = HyperliteMarkdownParser.linkingIssueReferences
        expect(link("Closes #146 and GH-12", "o/r") ==
               "Closes [#146](https://github.com/o/r/issues/146) and [GH-12](https://github.com/o/r/issues/12)",
               "issue references link to the repository's issues")
        expect(link("see lsmc-bio/labcore#1133", "o/r") ==
               "see [lsmc-bio/labcore#1133](https://github.com/lsmc-bio/labcore/issues/1133)",
               "cross-repository references link to their repository")
        expect(link("[#5](https://x) and https://github.com/o/r/pull/9#issuecomment-1", "o/r") ==
               "[#5](https://x) and https://github.com/o/r/pull/9#issuecomment-1",
               "existing links and URL fragments stay untouched")
        let rendered = HyperliteMarkdownParser.inline("Closes #7", repository: "o/r")
        expect(rendered.runs.contains { $0.link?.absoluteString == "https://github.com/o/r/issues/7" },
               "rendered text carries a clickable issue link")
        expect(HyperliteMarkdownParser.blocks("~~~\na ``` b\n~~~\n1) one\n1000. big") == [
            .code("a ``` b"), .listItem(marker: "1)", depth: 0, text: "one"),
            .listItem(marker: "1000.", depth: 0, text: "big"),
        ], "tilde fences close only on a tilde fence; ) and long ordered markers are list items")
        expect(HyperliteMarkdownParser.blocks("```swift\nlet a = 1\n``` not a closer\n```") == [
            .code("let a = 1\n``` not a closer"),
        ], "a fence followed by text is code, not a closer")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
