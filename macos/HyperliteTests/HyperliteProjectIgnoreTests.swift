import Foundation

enum HyperliteProjectIgnoreTests {
    static func run() throws {
        let json = Data("""
        [{"id": "/a", "name": "a", "path": "/a", "status": "cached", "pull_requests": [], "ignored": true},
         {"id": "/b", "name": "b", "path": "/b", "status": "current", "pull_requests": []}]
        """.utf8)
        let projects = try HyperliteJSON.decoder.decode([HyperliteProjectPullRequests].self, from: json)
        expect(projects[0].isIgnored, "an ignored project decodes as ignored")
        expect(!projects[1].isIgnored, "a project without the key is watched")
        expect(HyperliteProjectIgnorePresentation.iconName(ignored: false) == "eye",
               "watched projects show an open eye")
        expect(HyperliteProjectIgnorePresentation.iconName(ignored: true) == "eye.slash",
               "ignored projects show a closed eye")
        expect(HyperliteProjectIgnorePresentation.command(ignored: true) == "ignore" &&
               HyperliteProjectIgnorePresentation.command(ignored: false) == "watch",
               "the eye maps to the projects ignore/watch helper commands")
        expect(HyperliteProjectIgnorePresentation.buttonLabel(repository: "dewey", ignored: true)
            .hasPrefix("Watch dewey"), "an ignored project offers to watch again")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
