import Foundation

/// The app is written in Turkish; other languages are tables keyed by that Turkish text, in the bundle's
/// `<language>.lproj/Localizable.strings`. A Mac set to Turkish sees the text as written, any other Mac sees English.
///
/// Text reaches the screen already built ("Ekip Kur: Arayüz"), so a key with `%@` in it is also a pattern:
/// the parts in the placeholders are carried over into the translation. Anything not in the table shows as it is,
/// which is right for names, paths and commands.
public enum Loc {
    private static let lock = NSLock()
    private static var loaded = false
    private static var table: [String: String] = [:]
    private static var patterns: [(regex: NSRegularExpression, format: String)] = []
    private static var cache: [String: String] = [:]
    private static var forced = false

    /// The language the bundle settled on: the person's choice in Enterm, else the system's, else English.
    public static var language: String {
        chosen ?? Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// A choice made while the app runs. The phone switches at once; the Mac's menus follow on the next launch.
    private static var chosen: String? = override

    public static var isTurkish: Bool { language.hasPrefix("tr") }

    /// Dates and numbers follow the language the words are in.
    public static var locale: Locale { Locale(identifier: isTurkish ? "tr_TR" : "en_US") }

    /// The choice made in Settings. Takes effect on the next launch, as every Mac app's language does.
    public static var override: String? {
        get { (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first.flatMap { ["tr", "en"].contains($0) ? $0 : nil } }
        set {
            if let newValue { UserDefaults.standard.set([newValue], forKey: "AppleLanguages") } else { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
            lock.lock()
            defer { lock.unlock() }
            // System again: the system's first language this app has, read now rather than at launch.
            chosen = newValue ?? Bundle.preferredLocalizations(from: Bundle.main.localizations.filter { $0 != "Base" }, forPreferences: Locale.preferredLanguages).first
            loaded = false
            table = [:]
            patterns = []
            cache = [:]
        }
    }

    public static func t(_ text: String) -> String {
        guard forced || !isTurkish, !text.isEmpty else { return text }
        lock.lock()
        defer { lock.unlock() }
        load()
        if let direct = table[text] { return direct }
        if let known = cache[text] { return known }
        var result = text
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(in: text, range: range) else { continue }
            let parts = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
            result = fill(pattern.format, parts)
            break
        }
        // Names and paths change all the time; the memory stays small.
        if cache.count > 4000 { cache.removeAll(keepingCapacity: true) }
        cache[text] = result
        return result
    }

    /// A placeholder as format strings write it: `%@`, `%1$@`, `%d`, `%02d`, `%.1f`, `%lld`. `%%` is a percent sign.
    private static let specifier = try! NSRegularExpression(pattern: #"%%|%(?:([0-9]+)\$)?[-+ 0#]*[0-9]*(?:\.[0-9]+)?(?:ll|l|h)?[@dfsiuxX]"#)

    /// The pieces of a format: fixed text, and placeholders with the position they take, if they name one.
    private enum Piece { case text(String), slot(Int?) }

    private static func pieces(_ format: String) -> [Piece] {
        var result: [Piece] = []
        var last = format.startIndex
        for match in specifier.matches(in: format, range: NSRange(format.startIndex..., in: format)) {
            guard let range = Range(match.range, in: format) else { continue }
            if last < range.lowerBound { result.append(.text(String(format[last..<range.lowerBound]))) }
            if format[range] == "%%" {
                result.append(.text("%"))
            } else {
                let position = Range(match.range(at: 1), in: format).flatMap { Int(format[$0]) }
                result.append(.slot(position))
            }
            last = range.upperBound
        }
        if last < format.endIndex { result.append(.text(String(format[last...]))) }
        return result
    }

    /// The translation with the parts of the shown text put where its placeholders are.
    static func fill(_ format: String, _ parts: [String]) -> String {
        var out = ""
        var next = 0
        for piece in pieces(format) {
            switch piece {
            case .text(let text): out += text
            case .slot(let position):
                let index = position.map { $0 - 1 } ?? next
                if index >= 0, index < parts.count { out += parts[index] }
                next += 1
            }
        }
        return out
    }

    /// A key with placeholders, as a pattern that matches the built text.
    static func pattern(for key: String) -> NSRegularExpression? {
        let all = pieces(key)
        guard all.contains(where: { if case .slot = $0 { return true } else { return false } }) else { return nil }
        // "%@ %@" would match any text at all: a pattern needs some fixed words of its own.
        let fixed = all.map { if case .text(let text) = $0 { return text } else { return "" } }.joined().filter { $0.isLetter }
        guard fixed.count >= 3 else { return nil }
        var regex = "^"
        for piece in all {
            switch piece {
            case .text(let text): regex += NSRegularExpression.escapedPattern(for: text)
            case .slot: regex += "(.+?)"
            }
        }
        return try? NSRegularExpression(pattern: regex + "$", options: [.dotMatchesLineSeparators])
    }

    private static func load() {
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language),
              let dictionary = NSDictionary(contentsOf: url) as? [String: String] else { return }
        apply(dictionary)
    }

    /// Tests hand over a table directly and translate whatever the Mac's language.
    public static func useForTesting(_ dictionary: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        forced = true
        apply(dictionary)
    }

    private static func apply(_ dictionary: [String: String]) {
        table = [:]
        patterns = []
        cache = [:]
        loaded = true
        for (key, value) in dictionary {
            if let regex = pattern(for: key) {
                patterns.append((regex, value))
            } else {
                table[key] = value
            }
        }
        // The longest fixed text first, so "Ekip %@: %@" wins over "%@: %@".
        patterns.sort { $0.regex.pattern.count > $1.regex.pattern.count }
    }
}

/// Short for `Loc.t`, where text is put on screen.
public func L(_ text: String) -> String { Loc.t(text) }

/// The same Turkish word can mean two things ("Açık": light theme, or on). The table holds such a word
/// as "context::word"; without an entry it falls back to the plain word.
public func L(_ text: String, context: String) -> String {
    let keyed = Loc.t("\(context)::\(text)")
    return keyed == "\(context)::\(text)" ? Loc.t(text) : keyed
}

extension Loc {
    /// A percentage the way the language writes it: "%40" in Turkish, "40%" in English.
    public static func percent(_ value: Int) -> String { isTurkish ? "%\(value)" : "\(value)%" }
}
