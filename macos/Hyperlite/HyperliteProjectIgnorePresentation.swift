import Foundation

/// Copy and icons for the per-project ignore eye. An open eye means the
/// project is watched; a closed eye means it is ignored and never fetched.
enum HyperliteProjectIgnorePresentation {
    static let ignoredText = "ignored"

    static func iconName(ignored: Bool) -> String {
        ignored ? "eye.slash" : "eye"
    }

    static func buttonLabel(repository: String, ignored: Bool) -> String {
        ignored
            ? "Watch \(repository) again and fetch its open pull requests"
            : "Ignore \(repository): collapse it and stop fetching its pull requests"
    }

    static func command(ignored: Bool) -> String {
        ignored ? "ignore" : "watch"
    }
}
