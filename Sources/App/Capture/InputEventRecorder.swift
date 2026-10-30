import AppKit
import AppCore
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
    /// Typing: what the field held when the typing stopped, only with typed text turned on.
    var text: String?
    /// The web page the click or typing happened on, only with reading the browser URL turned on.
    var url: String?
}

/// Records clicks and shortcut key presses with global event monitors.
/// Key presses that type are stored as "typing…"; what the field holds is read from the field
/// itself after a pause, only when the person turned that on, and never from password fields.
@MainActor
final class InputEventRecorder {
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private(set) var events: [InputEvent] = []
    private var retention: Double = 300
    private(set) var readsTypedText = false
    private(set) var readsPages = false
    private var typingRuns = TypingRuns()
    /// The run whose field is still kept for reading, so it is read once more when it ends.
    private var openRun: TypingRuns.Run?
    /// Counts typing pauses, so only the last scheduled read of a run does anything.
    private var typingReadNumber = 0
    /// How long typing has to stop before the field is read.
    static let typingPause: Double = 0.7
    /// Markers up to this host time were already used to extend a saved clip.
    private var usedMarkersUntil: Double = 0

    static var hasAccessibilityAccess: Bool {
        return AXIsProcessTrusted()
    }

    static func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start(clicks: Bool, keys: Bool, typedText: Bool, pages: Bool, retentionSeconds: Double) {
        stop()
        retention = retentionSeconds + 60
        readsTypedText = typedText
        readsPages = pages
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

    /// The person changed "Show what I type in steps" or "Read the browser tab URL": applies at
    /// once, and what is no longer wanted is removed from the events kept so far.
    func setPrivacy(typedText: Bool, pages: Bool) {
        readsTypedText = typedText
        readsPages = pages
        for index in events.indices {
            if !typedText {
                events[index].text = nil
            }
            if !pages {
                events[index].url = nil
            }
        }
    }

    private func recordClick(at location: CGPoint) {
        let time = CACurrentMediaTime()
        endTypingRun()
        append(InputEvent(kind: .click, time: time, x: location.x, y: location.y, label: ""))
        ElementInspector.describe(at: location, readPage: readsPages) { element in
            guard let found = element else { return }
            Task { @MainActor in
                self.nameClick(at: time, element: found)
            }
        }
    }

    private func nameClick(at time: Double, element: ElementInspector.Element) {
        for index in events.indices.reversed() where events[index].kind == .click && events[index].time == time {
            events[index].target = element.target
            events[index].app = element.app
            if readsPages && !element.url.isEmpty {
                events[index].url = element.url
            }
            return
        }
    }

    /// A typing run starts: its event is at the first key, and the field it goes into is named now,
    /// before Tab or a click can move the focus.
    private func startTypingRun(_ run: TypingRuns.Run) {
        // The run before it ended with a pause.
        finishOpenRun()
        openRun = run
        append(InputEvent(kind: .key, time: run.start, x: 0, y: 0, label: InputEventRecorder.typingLabel))
        ElementInspector.beginField(run: run.id, readPage: readsPages) { field in
            guard let found = field else { return }
            Task { @MainActor in
                self.nameTyping(run, field: found)
            }
        }
    }

    /// After a pause in typing, what the run's field holds (with typed text turned on).
    private func scheduleValueRead(_ run: TypingRuns.Run) {
        typingReadNumber += 1
        let number = typingReadNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + InputEventRecorder.typingPause) {
            MainActor.assumeIsolated {
                if number != self.typingReadNumber || self.openRun?.id != run.id { return }
                self.readValue(of: run, thenForget: false)
            }
        }
    }

    /// A click, a key that does not type, or the next run: the run's field is read a last time
    /// and let go.
    private func endTypingRun() {
        _ = typingRuns.interrupted()
        finishOpenRun()
    }

    private func finishOpenRun() {
        guard let run = openRun else { return }
        openRun = nil
        readValue(of: run, thenForget: true)
    }

    private func readValue(of run: TypingRuns.Run, thenForget: Bool) {
        if !readsTypedText {
            if thenForget {
                ElementInspector.endField(run: run.id)
            }
            return
        }
        ElementInspector.readValue(run: run.id) { value in
            Task { @MainActor in
                if let text = value, !text.isEmpty {
                    self.setTypedText(text, of: run)
                }
            }
        }
        if thenForget {
            ElementInspector.endField(run: run.id)
        }
    }

    private func typingEventIndex(of run: TypingRuns.Run) -> Int? {
        for index in events.indices.reversed() where events[index].kind == .key && events[index].label == InputEventRecorder.typingLabel && events[index].time == run.start {
            return index
        }
        return nil
    }

    private func nameTyping(_ run: TypingRuns.Run, field: ElementInspector.Field) {
        guard let index = typingEventIndex(of: run) else { return }
        events[index].target = field.target
        events[index].app = field.app
        if readsPages && !field.url.isEmpty {
            events[index].url = field.url
        }
    }

    private func setTypedText(_ text: String, of run: TypingRuns.Run) {
        // The setting may have been turned off while the field was read.
        guard readsTypedText, let index = typingEventIndex(of: run) else { return }
        events[index].text = String(text.prefix(200))
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
        // A run of plain typing is one "typing…" event at its first key.
        if label == InputEventRecorder.typingLabel {
            let typed = typingRuns.typed(at: now)
            if typed.isNew {
                startTypingRun(typed.run)
            }
            scheduleValueRead(typed.run)
            return
        }
        // Tab, Enter or a shortcut ends the run before the focus moves on.
        endTypingRun()
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
        return label(keyCode: event.keyCode, flags: event.modifierFlags, characters: event.charactersIgnoringModifiers ?? "")
    }

    /// What a key press shows in a clip. Shortcuts with ⌘ or ⌃ are shown; anything that types a
    /// character, including ⌥ and ⌥⇧ combinations (™, ©, letters on many layouts), is masked so
    /// passwords and messages never end up in a clip.
    static func label(keyCode: UInt16, flags allFlags: NSEvent.ModifierFlags, characters: String) -> String {
        let flags = allFlags.intersection(.deviceIndependentFlagsMask)
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
        let isShortcut = flags.contains(.command) || flags.contains(.control)
        if let name = special[keyCode] {
            if modifiers.isEmpty { return name }
            return modifiers + " " + name
        }
        if isShortcut {
            // ⌘C, not ⌘С, with a Russian layout.
            return modifiers + " " + LatinKeys.key(forKeyCode: keyCode, typed: characters).uppercased()
        }
        return typingLabel
    }
}
