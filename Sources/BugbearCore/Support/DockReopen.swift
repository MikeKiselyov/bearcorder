/// A click on Bugbear's Dock icon. The icon is there while a window is open; a click brings the
/// windows back (also from the Dock when minimized). With no window left the icon has nothing to
/// show, so the menu opens instead and the icon goes.
public enum DockReopen {
    public enum Action: Equatable {
        case showWindows
        case openMenu
    }

    public static func action(openWindowCount: Int) -> Action {
        if openWindowCount > 0 {
            return .showWindows
        }
        return .openMenu
    }
}
