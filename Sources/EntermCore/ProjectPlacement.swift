import Foundation

/// Which project tab a new session joins.
public enum ProjectPlacement {
    public static func name(for folder: String, home: String) -> String {
        if folder == home || folder.isEmpty { return "Ana Klasör" }
        return (folder as NSString).lastPathComponent
    }

    /// A session opened in another folder gets that folder's tab, so the tab on screen always says
    /// where the person is. The tab on screen keeps a session in its own folder or below it, and a
    /// plain terminal at home.
    public static func project(folder: String, home: String, active: String?, activeFolders: [String], startingFromHome: Bool) -> String {
        let own = name(for: folder, home: home)
        guard let active, !startingFromHome else { return own }
        if folder.isEmpty || folder == home || own == active { return active }
        let inside = activeFolders.contains { base in
            base != home && !base.isEmpty && (folder == base || folder.hasPrefix(base.hasSuffix("/") ? base : base + "/"))
        }
        return inside ? active : own
    }
}
