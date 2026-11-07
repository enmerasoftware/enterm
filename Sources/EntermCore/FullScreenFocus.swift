/// While one box fills the window, the box picked from the strip, the rail or the inbox takes its place;
/// otherwise the keys would go to a session that is not on screen.
public enum FullScreenFocus {
    public static func shown(current: UInt32?, focusing: UInt32?, visible: [UInt32]) -> UInt32? {
        guard let current, let focusing, visible.contains(focusing) else { return current }
        return focusing
    }
}
