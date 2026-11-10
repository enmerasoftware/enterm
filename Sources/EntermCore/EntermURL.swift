import Foundation

/// `enterm://` addresses: from a script, a note, a README or another app.
/// Anything that starts a program is confirmed in the app first; a web page cannot start one silently.
public enum EntermURL: Equatable {
    /// `enterm://open?path=~/Projeler/app&program=claude&name=Arayüz&task=...`
    case open(path: String, program: String?, name: String?, task: String?)
    /// `enterm://session/<name>`: bring a session to the front.
    case session(String)
    /// `enterm://settings/<tab>`
    case settings(String)
    /// `enterm://board`, `enterm://commands`, `enterm://skills`
    case page(String)

    public static func parse(_ url: URL) -> EntermURL? {
        guard url.scheme?.lowercased() == "enterm", let host = url.host?.lowercased() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? {
            items.first { $0.name == key }?.value.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        let rest = url.pathComponents.filter { $0 != "/" }.first
        switch host {
        case "open":
            guard let path = value("path") else { return nil }
            return .open(path: path, program: value("program"), name: value("name"), task: value("task"))
        case "session":
            return rest.map { .session($0) }
        case "settings":
            return .settings(rest ?? "programs")
        case "board", "commands", "skills":
            return .page(host)
        default:
            return nil
        }
    }
}
