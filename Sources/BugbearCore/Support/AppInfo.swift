/// The app's name in one place.
public enum AppInfo {
    /// The name people see: menus, windows, messages, saved file names and the .app in Finder.
    /// Change it here only; scripts read it with scripts/lib/app-name.sh.
    public static let name = "Bugbear"
    /// Folder names already on people's Macs (captures, logs, the default save folder). They stay
    /// when the name changes, or saved captures and settings would be left behind.
    public static let storageName = "Bugbear"
}
