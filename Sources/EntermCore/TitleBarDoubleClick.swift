/// What a double click on the window's top bar does. It follows the choice in System Settings
/// ("Double-click a window's title bar to"), the way every Mac window does.
public enum TitleBarDoubleClick: Equatable {
    case zoom
    case minimize
    case none

    public static func action(setting: String?, legacyMinimize: Bool) -> TitleBarDoubleClick {
        switch setting {
        case "Minimize": return .minimize
        case "None": return .none
        case nil: return legacyMinimize ? .minimize : .zoom
        default: return .zoom
        }
    }
}
