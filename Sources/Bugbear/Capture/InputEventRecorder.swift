import AppKit
import ApplicationServices
import QuartzCore

/// A click or key press recorded while the buffer runs.
struct InputEvent: Codable, Equatable {
    enum Kind: String, Codable {
        case click
        case key
        /// A moment the user marked with ⌥⇧M: "the bug is here".
        case marker
    }

    var kind: Kind
    /// Host time (CACurrentMediaTime) when recorded; relative clip time after export.
    var time: Double
    /// Clicks: global AppKit point while recording, normalized clip position (origin top-left) once exported.
    var x: Double
    var y: Double
    /// Key label like "⌘ Enter". Keys only.
    var label: String
    /// Clicks: the element under the click, e.g. `"Submit" button`, when Accessibility is allowed.
    var target: String?
    /// Clicks: the app that received the click.
    var app: String?
}

/// Records clicks and shortcut key presses with global event monitors.
/// Plain typing is never stored as text: it collapses to "typing…" so passwords stay out of clips.
@MainActor
final class InputEventRecorder {
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private(set) var events: [InputEvent] = []
    private var retention: Double = 300
    /// Markers up to this host time were already used to extend a saved clip.
    private var usedMarkersUntil: Double = 0

    static var hasAccessibilityAccess: Bool {
        return AXIsProcessTrusted()
    }

    static func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start(clicks: Bool, keys: Bool, retentionSeconds: Double) {
        stop()
        retention = retentionSeconds + 60
        if clicks {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                let location = NSEvent.mouseLocation
                Task { @MainActor in
                    self?.recordClick(at: location)
                }
            }
        }
        if keys {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                let label = InputEventRecorder.label(for: event)
                Task { @MainActor in
                    self?.recordKey(label)
                }
            }
        }
    }

    func stop() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitor = nil
        keyMonitor = nil
    }

    /// Marks the current moment. Works even when click and key recording are off.
    func mark() {
        append(InputEvent(kind: .marker, time: CACurrentMediaTime(), x: 0, y: 0, label: ""))
    }

    /// Host time of the oldest marker not used by a previous save, then marks all of them as used.
    func takeOldestNewMarker() -> Double? {
        var oldest: Double? = nil
        for event in events where event.kind == .marker && event.time > usedMarkersUntil {
            if oldest == nil {
                oldest = event.time
            }
        }
        usedMarkersUntil = CACurrentMediaTime()
        return oldest
    }

    private func recordClick(at location: CGPoint) {
        let time = CACurrentMediaTime()
        append(InputEvent(kind: .click, time: time, x: location.x, y: location.y, label: ""))
        ElementInspector.describe(at: location) { element in
            guard let found = element else { return }
            Task { @MainActor in
                self.nameClick(at: time, target: found.target, app: found.app)
            }
        }
    }

    private func nameClick(at time: Double, target: String, app: String) {
        for index in events.indices.reversed() where events[index].kind == .click && events[index].time == time {
            events[index].target = target
            events[index].app = app
            return
        }
    }

    /// Events of the last `seconds`, timed relative to now (negative), for a screenshot's steps.
    func recentEvents(seconds: Double) -> [InputEvent] {
        let now = CACurrentMediaTime()
        var result: [InputEvent] = []
        for event in events where event.time >= now - seconds {
            var copy = event
            copy.time = event.time - now
            copy.x = 0
            copy.y = 0
            result.append(copy)
        }
        return result
    }

    private func recordKey(_ label: String) {
        let now = CACurrentMediaTime()
        // Merge a run of plain typing into one "typing…" marker.
        if label == InputEventRecorder.typingLabel, let last = events.last, last.kind == .key, last.label == label, now - last.time < 1.5 {
            events[events.count - 1].time = now
            return
        }
        append(InputEvent(kind: .key, time: now, x: 0, y: 0, label: label))
    }

    private func append(_ event: InputEvent) {
        events.append(event)
        let cutoff = event.time - retention
        while let first = events.first, first.time < cutoff {
            events.removeFirst()
        }
    }

    /// Events mapped onto an exported clip: clip-relative times and normalized click positions.
    func events(for clip: ClipExport) -> [InputEvent] {
        var result: [InputEvent] = []
        for event in events {
            guard let time = clip.outputTime(forHost: event.time) else { continue }
            var copy = event
            copy.time = time
            if event.kind == .click {
                guard let point = clip.layout.normalizedPoint(forGlobal: CGPoint(x: event.x, y: event.y)) else { continue }
                copy.x = point.x
                copy.y = point.y
            }
            result.append(copy)
        }
        return result
    }

    static let typingLabel = "typing…"

    static func label(for event: NSEvent) -> String {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = ""
        if flags.contains(.control) { modifiers += "⌃" }
        if flags.contains(.option) { modifiers += "⌥" }
        if flags.contains(.shift) { modifiers += "⇧" }
        if flags.contains(.command) { modifiers += "⌘" }

        let special: [UInt16: String] = [
            36: "Enter", 76: "Enter", 48: "Tab", 49: "Space", 51: "Delete", 117: "Fwd Delete",
            53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End",
            116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        let hasCommandLike = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        if let name = special[event.keyCode] {
            if modifiers.isEmpty { return name }
            return modifiers + " " + name
        }
        // Characters only with ⌘/⌃/⌥: shortcuts like ⌘C. Plain typing is masked.
        if hasCommandLike {
            let character = (event.charactersIgnoringModifiers ?? "").uppercased()
            return modifiers + " " + character
        }
        return typingLabel
    }
}
