/// The app's name in one place.
public enum AppInfo {
    /// The name people see: menus, windows, messages, saved file names and the .app in Finder. It is
    /// also the executable and process, and the folders on disk (Application Support, Logs, the default
    /// save folder). Change it with scripts/dev/rename-app.sh; scripts read it with scripts/lib/app-name.sh.
    public static let name = "Bearcorder"

    /// The name in lower case with "-" for spaces, for the places below.
    public static var slug: String {
        return name.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// The GitHub repository: where problem reports go and where the installer gets the source.
    public static var repository: String {
        return "MikeKiselyov/\(slug)"
    }

    /// The bundle id of copies built without APP_BUNDLE_ID, as the installer builds them.
    public static var defaultBundleId: String {
        return "io.github.\(slug).app"
    }

    /// The hidden folder in the home folder where the installer keeps the source for updates.
    public static var sourceFolder: String {
        return ".\(slug)"
    }
}
