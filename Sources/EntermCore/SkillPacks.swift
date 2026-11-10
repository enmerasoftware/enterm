import Foundation

/// The preset skills that ship with Enterm. Each pack is a Claude Code plugin folder:
/// `.claude-plugin/plugin.json` and `skills/<name>/SKILL.md`. A session gets the packs that are on through
/// `--plugin-dir`, so nothing is written to the person's own configuration.
public struct SkillPack: Equatable, Identifiable {
    public struct Skill: Equatable, Identifiable {
        public var name: String
        public var description: String
        public var id: String { name }
        /// What the person types in a session to run it by name.
        public func command(pack: String) -> String { "/\(pack):\(name)" }
    }

    public var id: String
    public var description: String
    public var folder: URL
    public var skills: [Skill]

    /// The packs in a folder, in a fixed order: the known packs first, then any added later by name.
    public static func packs(in root: URL) -> [SkillPack] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: root.path) else { return [] }
        let order = ["code", "video", "image"]
        let sorted = names.sorted { (order.firstIndex(of: $0) ?? order.count, $0) < (order.firstIndex(of: $1) ?? order.count, $1) }
        return sorted.compactMap { name in
            let folder = root.appendingPathComponent(name, isDirectory: true)
            let manifest = folder.appendingPathComponent(".claude-plugin/plugin.json")
            guard let data = try? Data(contentsOf: manifest),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["name"] as? String else { return nil }
            let skillsFolder = folder.appendingPathComponent("skills", isDirectory: true)
            let skills = ((try? manager.contentsOfDirectory(atPath: skillsFolder.path)) ?? []).sorted().compactMap { entry -> Skill? in
                let file = skillsFolder.appendingPathComponent(entry).appendingPathComponent("SKILL.md")
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                let front = frontMatter(text)
                return Skill(name: front["name"] ?? entry, description: front["description"] ?? "")
            }
            return SkillPack(id: id, description: object["description"] as? String ?? "", folder: folder, skills: skills)
        }
    }

    /// The simple `key: value` lines between the opening and closing `---`.
    public static func frontMatter(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var result: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    /// Where the packs are: next to the app's programs inside the bundle, or a folder named in `ENTERM_SKILLS_DIR`.
    public static func root(executable: String, environment: [String: String]) -> URL? {
        if let named = environment["ENTERM_SKILLS_DIR"], !named.isEmpty { return URL(fileURLWithPath: named, isDirectory: true) }
        let bundled = URL(fileURLWithPath: executable).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/skills", isDirectory: true)
        return FileManager.default.fileExists(atPath: bundled.path) ? bundled : nil
    }

    /// The `--plugin-dir` arguments for the packs that are on. A pack that is gone is skipped, never an error.
    public static func pluginArguments(enabled: [String], root: URL?) -> [String] {
        guard let root, !enabled.isEmpty else { return [] }
        return packs(in: root).filter { enabled.contains($0.id) }.flatMap { ["--plugin-dir", $0.folder.path] }
    }
}
