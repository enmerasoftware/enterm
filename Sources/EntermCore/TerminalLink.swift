import Foundation

/// What a piece of terminal text points to when it is clicked.
public enum TerminalLink {
    public enum Target: Equatable {
        case web(URL)
        case path(String)
    }

    /// Kinds of file that do something when opened, rather than show something.
    public static let runnableExtensions: Set<String> = [
        "app", "applescript", "command", "dmg", "fileloc", "inetloc", "jar", "mpkg", "pkg", "scpt", "terminal", "tool", "url", "webloc", "workflow",
    ]

    private static let pattern = try? NSRegularExpression(pattern:
        #"https?://[^\s'"`<>()\[\]{}]+|(?<![\w/.~-])(?:~/|\.{1,2}/|/|[\w.\-]+/)[\w.\-~/+@%]*(?::[0-9]+){0,2}"#)

    /// The web address or path under one character of a line of terminal text.
    public static func find(in line: String, at offset: Int) -> String? {
        guard let pattern else { return nil }
        for match in pattern.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            guard let range = Range(match.range, in: line) else { continue }
            let start = line.distance(from: line.startIndex, to: range.lowerBound)
            let end = line.distance(from: line.startIndex, to: range.upperBound)
            guard offset >= start, offset < end else { continue }
            let found = String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            return found.count > 1 ? found : nil
        }
        return nil
    }

    public static func target(_ text: String, cwd: String?, home: String) -> Target? {
        let link = text.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: link), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" { return .web(url) }
            if scheme == "file" { return url.path.isEmpty ? nil : .path(url.path) }
            if link.contains("://") || link.hasPrefix("mailto:") { return nil }
        }
        return path(withoutLineNumbers(link), cwd: cwd, home: home).map(Target.path)
    }

    private static func path(_ text: String, cwd: String?, home: String) -> String? {
        var path = text
        if path == "~" || path.hasPrefix("~/") {
            path = home + path.dropFirst()
        } else if !path.hasPrefix("/") {
            guard let cwd, !path.hasPrefix("$") else { return nil }
            path = cwd + "/" + path
        }
        return (path as NSString).standardizingPath
    }

    /// Compilers and agents write `file.swift:12:5`.
    private static func withoutLineNumbers(_ text: String) -> String {
        guard let range = text.range(of: #"(:[0-9]+){1,2}$"#, options: .regularExpression) else { return text }
        return String(text[..<range.lowerBound])
    }
}
