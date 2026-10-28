// A release has no automation, self-test or media tools (see DevTools/): nothing can drive it from
// outside, whatever is in its defaults. The app asks only whether automation is on.
#if !AUTOMATION
enum Automation {
    static let isEnabled = false

    static func install() {}
}
#endif
