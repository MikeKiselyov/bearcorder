import AppKit
import BugbearCore
import Carbon.HIToolbox
import Observation

/// A key plus modifiers, stored the way Carbon's RegisterEventHotKey wants it.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon flags: cmdKey, optionKey, shiftKey, controlKey.
    var modifiers: UInt32
    /// What the key prints, e.g. "1" or "M".
    var key: String

    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    /// The same in words, for people who do not know the symbols: "Option + Shift + 1".
    var spoken: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("Control") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Command") }
        parts.append(key)
        return parts.joined(separator: " + ")
    }

    static func optionShift(_ keyCode: Int, _ key: String) -> Shortcut {
        return Shortcut(keyCode: UInt32(keyCode), modifiers: UInt32(optionKey | shiftKey), key: key)
    }

    /// From a key press in the recorder. Nil without ⌘, ⌥ or ⌃: plain keys would break typing everywhere.
    static func from(_ event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let hasCommandLike = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        if !hasCommandLike { return nil }
        var key = (event.charactersIgnoringModifiers ?? "").uppercased()
        let special: [UInt16: String] = [
            49: "Space", 36: "↩", 48: "⇥", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = special[event.keyCode] {
            key = name
        }
        // With ⌥ the character is often a symbol ("¡" for 1); show the plain key instead.
        if let plain = Shortcut.plainKeys[event.keyCode] {
            key = plain
        }
        if key.isEmpty { return nil }
        return Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
    }

    static let plainKeys: [UInt16: String] = LatinKeys.names
}

/// Everything a global shortcut can do. The order is the order in Settings.
enum HotKeyAction: String, CaseIterable, Identifiable, Codable {
    case saveShort
    case saveMinute
    case saveBuffer
    case screenshotArea
    case screenshotWindow
    case scrollingScreenshot
    case copyText
    case recordToggle
    case recordPause
    case draw
    case mark
    case camera
    case toolbox
    case ruler
    case pickColor
    case openMenu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saveShort: return "Save the last 30 s"
        case .saveMinute: return "Save the last minute"
        case .saveBuffer: return "Save the whole buffer"
        case .screenshotArea: return "Screenshot an area"
        case .screenshotWindow: return "Screenshot a window"
        case .scrollingScreenshot: return "Scrolling screenshot"
        case .copyText: return "Copy text from screen"
        case .recordToggle: return "Start / stop recording"
        case .recordPause: return "Pause / resume recording"
        case .draw: return "Draw on screen"
        case .mark: return "Mark the moment"
        case .camera: return "Camera bubble"
        case .toolbox: return "Dev toolbox"
        case .ruler: return "Measure on screen"
        case .pickColor: return "Pick a color"
        case .openMenu: return "Open the \(AppInfo.name) menu"
        }
    }

    var defaultShortcut: Shortcut? {
        switch self {
        case .saveShort: return .optionShift(kVK_ANSI_1, "1")
        case .saveMinute: return .optionShift(kVK_ANSI_2, "2")
        case .saveBuffer: return .optionShift(kVK_ANSI_3, "3")
        case .screenshotArea: return .optionShift(kVK_ANSI_4, "4")
        case .screenshotWindow: return .optionShift(kVK_ANSI_5, "5")
        case .scrollingScreenshot: return nil
        case .copyText: return .optionShift(kVK_ANSI_O, "O")
        case .recordToggle: return .optionShift(kVK_ANSI_6, "6")
        case .recordPause: return .optionShift(kVK_ANSI_7, "7")
        case .draw: return .optionShift(kVK_ANSI_A, "A")
        case .mark: return .optionShift(kVK_ANSI_M, "M")
        case .camera: return .optionShift(kVK_ANSI_C, "C")
        case .toolbox: return .optionShift(kVK_ANSI_D, "D")
        case .ruler: return nil
        case .pickColor: return nil
        case .openMenu: return .optionShift(kVK_ANSI_B, "B")
        }
    }

    @MainActor
    func perform() {
        let app = AppState.shared
        switch self {
        case .saveShort: Task { await app.saveFromBuffer(seconds: 30) }
        case .saveMinute: Task { await app.saveFromBuffer(seconds: 60) }
        case .saveBuffer: Task { await app.saveFromBuffer(seconds: app.settings.bufferSeconds) }
        case .screenshotArea: Task { await app.takeScreenshot(.area) }
        case .screenshotWindow: Task { await app.takeScreenshot(.window) }
        case .scrollingScreenshot: Task { await app.takeScrollingScreenshot() }
        case .copyText: Task { await app.copyTextFromScreen() }
        case .recordToggle: Task { await app.toggleRecording() }
        case .recordPause: app.recording?.togglePause()
        case .draw: app.toggleDrawing()
        case .mark: app.markMoment()
        case .camera: Task { await app.setCamera(!app.cameraOn) }
        case .toolbox: app.openToolbox(tool: nil)
        case .ruler: app.startRuler()
        case .pickColor: app.pickColor()
        case .openMenu: app.toggleMenuPanel()
        }
    }
}

/// The user's shortcuts: defaults unless changed in Settings. Changes re-register at once.
@MainActor
@Observable
final class HotKeySettings {
    static let shared = HotKeySettings()

    private static let storageKey = "customHotKeys"

    /// Only actions the user changed; a nil value means "no shortcut".
    private(set) var overrides: [String: Shortcut?] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: HotKeySettings.storageKey) {
            overrides = HotKeySettings.decode(data)
        }
    }

    /// Changed shortcuts by action; a nil value is a shortcut turned off, which is not the same as
    /// no entry (the default shortcut).
    static func encode(_ overrides: [String: Shortcut?]) -> Data? {
        return try? JSONEncoder().encode(overrides)
    }

    static func decode(_ data: Data) -> [String: Shortcut?] {
        return (try? JSONDecoder().decode([String: Shortcut?].self, from: data)) ?? [:]
    }

    func shortcut(for action: HotKeyAction) -> Shortcut? {
        if let custom = overrides[action.rawValue] {
            return custom
        }
        return action.defaultShortcut
    }

    func text(for action: HotKeyAction) -> String {
        return shortcut(for: action)?.display ?? ""
    }

    /// "⌥⇧1 (Option + Shift + 1)" for instructions.
    func readable(for action: HotKeyAction) -> String {
        guard let current = shortcut(for: action) else { return "" }
        return "\(current.display) (\(current.spoken))"
    }

    /// "Option + Shift + 1".
    func spoken(for action: HotKeyAction) -> String {
        return shortcut(for: action)?.spoken ?? ""
    }

    /// The action that already uses this shortcut, if any.
    func owner(of shortcut: Shortcut, except action: HotKeyAction) -> HotKeyAction? {
        for other in HotKeyAction.allCases where other != action {
            if let existing = self.shortcut(for: other), existing.keyCode == shortcut.keyCode && existing.modifiers == shortcut.modifiers {
                return other
            }
        }
        return nil
    }

    func set(_ shortcut: Shortcut?, for action: HotKeyAction) {
        if shortcut == action.defaultShortcut {
            overrides[action.rawValue] = nil
        } else {
            overrides[action.rawValue] = .some(shortcut)
        }
        save()
    }

    func resetAll() {
        overrides = [:]
        save()
    }

    var isCustomized: Bool {
        return !overrides.isEmpty
    }

    private func save() {
        if let data = HotKeySettings.encode(overrides) {
            UserDefaults.standard.set(data, forKey: HotKeySettings.storageKey)
        }
        AppState.shared.registerHotKeys()
    }
}
