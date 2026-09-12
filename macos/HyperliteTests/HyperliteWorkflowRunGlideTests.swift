import Foundation

enum HyperliteWorkflowRunGlideTests {
    static func run() {
        let period = HyperliteWorkflowRunGlide.period
        let start = Date(timeIntervalSinceReferenceDate: 0)
        expect(HyperliteWorkflowRunGlide.progress(at: start) == 0, "glide starts at the left edge")
        let half = Date(timeIntervalSinceReferenceDate: period / 2)
        expect(abs(HyperliteWorkflowRunGlide.progress(at: half) - 1) < 0.0001, "half period reaches the right edge")
        let full = Date(timeIntervalSinceReferenceDate: period)
        expect(abs(HyperliteWorkflowRunGlide.progress(at: full)) < 0.0001, "full period returns to the left edge")
        var previous = -1.0
        for step in 0...20 {
            let value = HyperliteWorkflowRunGlide.progress(
                at: Date(timeIntervalSinceReferenceDate: period / 2 * Double(step) / 20)
            )
            expect(value >= previous, "outbound leg is monotone")
            previous = value
        }
        expect(HyperliteWorkflowRunGlide.facesRight(at: Date(timeIntervalSinceReferenceDate: period * 0.25)),
               "ghost faces right on the outbound leg")
        expect(!HyperliteWorkflowRunGlide.facesRight(at: Date(timeIntervalSinceReferenceDate: period * 0.75)),
               "ghost flips on the return leg")
        expect(
            abs(HyperliteWorkflowRunGlide.ghostOffset(at: half, trackWidth: 80, glyphWidth: 11) - 69) < 0.0001,
            "offset keeps the glyph inside the track"
        )
        expect(HyperliteWorkflowRunGlide.showsGlide(.running(since: start)), "running chips glide")
        expect(!HyperliteWorkflowRunGlide.showsGlide(.staleRunning(lastSeen: start)) &&
            !HyperliteWorkflowRunGlide.showsGlide(.success) && !HyperliteWorkflowRunGlide.showsGlide(.idle),
            "stale, completed, and idle chips never glide")
        expect(HyperliteWorkflowRunGlide.tickInterval >= 1.0 / 15.0, "tick rate stays well below display refresh")
        expect(!HyperliteWorkflowRunGlide.accessibilityPolling.isEmpty, "polling has VoiceOver copy")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
