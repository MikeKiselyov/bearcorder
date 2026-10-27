/// Who asked the app to quit. After a permission is switched on, System Settings offers
/// "Quit & Reopen", but it only sends Quit: a menu bar app is not opened again and the bear just
/// disappears. A Quit from System Settings is answered with a restart instead.
public enum QuitRequest {
    /// System Settings itself and its panes (the Privacy & Security pane is an extension with its
    /// own bundle id, and it is the one that sends Quit).
    public static func comesFromSystemSettings(senderBundleID: String?) -> Bool {
        guard let sender = senderBundleID else { return false }
        if sender == "com.apple.systempreferences" {
            return true
        }
        return sender.hasPrefix("com.apple.settings.")
    }
}
