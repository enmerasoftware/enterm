import Foundation

/// A key combination for a menu command.
public struct KeyCombo: Codable, Equatable, Hashable {
    public var key: String
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(_ key: String, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key.lowercased()
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    public var display: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        switch key {
        case "\r": text += "⏎"
        default: text += key.uppercased(with: Locale(identifier: "en_US"))
        }
        return text
    }

    /// A shortcut needs ⌘ or ⌃, otherwise it would take a key the terminal needs for typing.
    public var isUsable: Bool { (command || control) && !key.isEmpty }
}

public struct ShortcutBook: Codable, Equatable {
    public var overrides: [String: KeyCombo] = [:]
    public init() {}

    public static let defaults: [(id: String, title: String, combo: KeyCombo)] = [
        ("newTerminal", "Yeni Terminal", KeyCombo("t")),
        ("newSession", "Yeni Oturum", KeyCombo("n")),
        ("close", "Kutuyu Kapat", KeyCombo("w")),
        ("maximize", "Tam Ekran, Tümünü Gör", KeyCombo("\r")),
        ("details", "Ayrıntılar", KeyCombo("i")),
        ("stop", "Durdur", KeyCombo(".")),
        ("next", "Sonraki Oturum", KeyCombo("]")),
        ("previous", "Önceki Oturum", KeyCombo("[")),
        ("palette", "Komut Paleti", KeyCombo("k")),
        ("inbox", "Onay Kutusu", KeyCombo("o", shift: true)),
        ("board", "Pano", KeyCombo("b", shift: true)),
        ("manager", "Yönetici Görünümü", KeyCombo("y", shift: true)),
        ("browser", "Tarayıcı", KeyCombo("d", shift: true)),
        ("zoomIn", "Yakınlaştır", KeyCombo("=")),
        ("zoomOut", "Uzaklaştır", KeyCombo("-")),
        ("fit", "Sığdır", KeyCombo("0", option: true)),
        ("settings", "Ayarlar", KeyCombo(",")),
    ]

    /// System and editing keys stay where everyone expects them.
    public static let reserved = Set([KeyCombo("q"), KeyCombo("c"), KeyCombo("v"), KeyCombo("x"), KeyCombo("a"), KeyCombo("h"), KeyCombo("m")]
        + (1...9).map { KeyCombo("\($0)") })

    public func combo(for id: String) -> KeyCombo? {
        overrides[id] ?? Self.defaults.first { $0.id == id }?.combo
    }

    /// Who else holds this combination, or a note when the system reserves it.
    public func conflict(for combo: KeyCombo, assigningTo id: String) -> String? {
        if Self.reserved.contains(combo) { return "Sistem Kısayolu" }
        for item in Self.defaults where item.id != id {
            if self.combo(for: item.id) == combo { return item.title }
        }
        return nil
    }

    public static var file: URL { EntermPaths.support.appendingPathComponent("shortcuts.json") }
    public static func load() -> ShortcutBook { JSONStore.load(ShortcutBook.self, from: file) ?? ShortcutBook() }
    public func save() { JSONStore.save(self, to: Self.file) }
}
