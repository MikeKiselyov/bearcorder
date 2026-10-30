// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI
import AppCore

@MainActor
extension FeatureAutomation {
    static func runReports(_ name: String, _ argument: String, _ parts: [String], _ app: AppState) async -> String? {
        switch name {
        case "report-settings-save", "report-settings-restore":
            // report-settings-save:<file> keeps the person's fields and field choices in a file,
            // report-settings-restore:<file> puts them back exactly, whatever the values hold.
            let path = parts.count > 1 ? parts[1...].joined(separator: ":") : ""
            guard !path.isEmpty else { return "no file" }
            let url = URL(fileURLWithPath: path)
            if name == "report-settings-save" {
                let saved = SavedReportSettings(fields: app.settings.reportFields, hidden: app.settings.hiddenEnvironmentFields, renamed: app.settings.renamedEnvironmentFields)
                guard let data = try? JSONEncoder().encode(saved), (try? data.write(to: url)) != nil else { return "not saved" }
                return "saved fields=\(saved.fields.count)"
            }
            guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(SavedReportSettings.self, from: data) else { return "nothing saved" }
            app.settings.reportFields = saved.fields
            app.settings.hiddenEnvironmentFields = saved.hidden
            app.settings.renamedEnvironmentFields = saved.renamed
            return "restored fields=\(saved.fields.count)"

        case "fields-read":
            // The person's own fields as "fields:" takes them, to put them back after a test.
            var pairs: [String] = []
            for field in app.settings.reportFields {
                pairs.append("\(field.name)=\(field.value)")
            }
            return pairs.joined(separator: ",")

        case "fields":
            // fields:Stand=stage-3,Build=1.42  (empty clears)
            var fields: [EnvironmentSnapshot.Field] = []
            for pair in argument.split(separator: ",") {
                let pieces = pair.split(separator: "=", maxSplits: 1)
                if pieces.count == 2 {
                    fields.append(EnvironmentSnapshot.Field(name: String(pieces[0]), value: String(pieces[1])))
                }
            }
            app.settings.reportFields = fields
            return "fields=\(fields.count)"

        case "report":
            // report:markdown|jira, for the newest capture; the text goes to the clipboard.
            guard let latest = app.store.captures.first else { return "no capture" }
            var format = BugReport.Format.markdown
            if argument == "jira" {
                format = .jira
            }
            BugReportBuilder.copy(for: latest, timeMap: nil, format: format)
            return "copied format=\(format.rawValue) default=\(app.settings.bugReportFormat)"

        case "extras-latest":
            guard let latest = app.store.captures.first else { return "no capture" }
            var texts: [String] = []
            for field in latest.environment.extras ?? [] {
                texts.append("\(field.name)=\(field.value)")
            }
            return "extras=\(texts.joined(separator: ","))"

        case "guide-latest":
            // guide-latest:<count>:<folder>
            let count = Int(argument) ?? 2
            let folder = parts.count > 2 ? parts[2] : AppPaths.temporary.path
            var shots: [Capture] = []
            for capture in app.store.captures where capture.kind == .screenshot && shots.count < count {
                shots.append(capture)
            }
            if shots.count < count { return "only \(shots.count) screenshots" }
            WindowManager.shared.openStepGuide(captures: shots)
            let model = StepGuideModel(captures: shots)
            model.steps[0].caption = "Open the page"
            var blocks: [(image: CGImage, caption: String)] = []
            for step in model.steps {
                blocks.append((image: step.image, caption: step.caption))
            }
            let png = URL(fileURLWithPath: folder).appendingPathComponent("guide.png")
            let pdf = URL(fileURLWithPath: folder).appendingPathComponent("guide.pdf")
            guard let image = StepGuideRenderer.longImage(title: "E2E guide", steps: blocks) else { return "no image" }
            ImageFiles.write(image, to: png, type: "public.png")
            let wrote = StepGuideRenderer.writePDF(title: "E2E guide", steps: blocks, to: pdf)
            let pages = CGPDFDocument(pdf as CFURL)?.numberOfPages ?? 0
            return "steps=\(model.steps.count) png=\(image.width)x\(image.height) pdf=\(wrote) pages=\(pages)"

        case "compare-latest" where argument == "video":
            // compare-latest:video: the two newest clips side by side.
            var clips: [Capture] = []
            for capture in app.store.captures where capture.kind == .video && clips.count < 2 {
                clips.append(capture)
            }
            if clips.count < 2 { return "need 2 clips" }
            WindowManager.shared.openCompare(clips[1], clips[0])
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return "opened"

        case "compare-latest":
            var shots: [Capture] = []
            for capture in app.store.captures where capture.kind == .screenshot && shots.count < 2 {
                shots.append(capture)
            }
            if shots.count < 2 { return "need 2 screenshots" }
            WindowManager.shared.openCompare(shots[0], shots[1])
            guard let output = ScreenshotComparison.make(before: shots[1], after: shots[0]) else { return "no comparison" }
            return "regions=\(output.result.regions.count) changed=\(String(format: "%.3f", output.result.changedShare))"

        case "hotkey-set":
            // hotkey-set:<action>:<keyCode>:<cmd,shift,option,control>
            guard let action = HotKeyAction(rawValue: argument), parts.count > 3, let keyCode = UInt32(parts[2]) else { return "bad hotkey" }
            let shortcut = Shortcut(keyCode: keyCode, modifiers: carbonModifiers(parts[3]), key: "?")
            if let owner = HotKeySettings.shared.owner(of: shortcut, except: action) {
                return "conflict with \(owner.rawValue)"
            }
            HotKeySettings.shared.set(shortcut, for: action)
            return "set \(action.rawValue)=\(HotKeySettings.shared.text(for: action))"
        case "hotkey-reset":
            HotKeySettings.shared.resetAll()
            return "customized=\(HotKeySettings.shared.isCustomized)"
        case "post-move":
            // post-move:x,y (top-left screen points): moves the pointer there, no click.
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let x = Double(numbers[0]), let y = Double(numbers[1]) else { return "bad point" }
            CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 200_000_000)
            return "moved"

        case "screen-center":
            // screen-center:<index>: the middle of that display in top-left screen points.
            let index = Int(argument) ?? 0
            let screens = NSScreen.screens
            guard index >= 0 && index < screens.count else { return "no screen \(index)" }
            let mainHeight = screens[0].frame.maxY
            let frame = screens[index].frame
            return "x=\(Int(frame.midX)) y=\(Int(mainHeight - frame.midY)) count=\(screens.count)"

        case "post-text":
            // post-text:<words>: real typing of the words, one character at a time.
            if !FeatureAutomation.frontAppTakesTestKeys() {
                return "not in front: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")"
            }
            let words = parts.count > 1 ? parts[1...].joined(separator: ":") : ""
            for character in words {
                let units = Array(String(character).utf16)
                let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
                down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
                up?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            return "typed \(words.count)"

        case "post-key":
            // post-key:<keyCode>:<modifiers>: a real key press through the HID event tap.
            guard let keyCode = CGKeyCode(argument), parts.count > 2 else { return "bad key" }
            // Real keys go to the app in front. Only this app and the test browser may get them, so
            // a test never types into someone's chat or document. The app's own shortcuts are the
            // exception: macOS hands them to the app before any app sees them.
            if !FeatureAutomation.isOwnShortcut(keyCode: keyCode, flags: parts[2]) && !FeatureAutomation.frontAppTakesTestKeys() {
                return "not in front: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")"
            }
            let flags = cgFlags(parts[2])
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            down?.flags = flags
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            up?.flags = flags
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            return "posted"

        case "record-area":
            // record-area:x,y,w,h[:builtin|<display id>]: normalized on the screen under the pointer, or
            // on the built-in display or the display with that id.
            var picked = selection(argument)
            if parts.count > 2 {
                picked = nil
                for screen in NSScreen.screens {
                    let id = AppState.displayID(of: screen)
                    if (parts[2] == "builtin" && CGDisplayIsBuiltin(id) != 0) || parts[2] == "\(id)" {
                        picked = selection(argument, on: screen)
                    }
                }
            }
            guard let area = picked else { return "bad area" }
            await app.startRecording(target: .area, presetRegion: area)
            return "recording=\(app.recording != nil) outline=\(app.recordingOutline.windowCount) region=\(Int(area.global.width))x\(Int(area.global.height))"

        case "buffer-sizes":
            // The picture size of every display's buffer: id=WxH;id=WxH, the main display first.
            var texts: [String] = []
            for buffer in app.buffers {
                let size = buffer.size
                texts.append("\(buffer.displayID)=\(Int(size.width))x\(Int(size.height))")
            }
            return texts.joined(separator: ";")

        case "buffer-seconds":
            // Seconds of video the main display's buffer holds right now, 0 without a buffer. e2e waits
            // for enough history before a step that reaches back (a marker, a crash).
            guard let buffer = app.buffers.first else { return "0" }
            return String(format: "%.1f", buffer.heldSeconds(now: CACurrentMediaTime()))

        case "video-size-test":
            guard let clip = app.store.captures.first(where: { item in item.kind == .video }) else { return "no video" }
            let model = VideoEditorModel(capture: clip)
            model.addOverlay(kind: .arrow, start: CGPoint(x: 0.2, y: 0.2), end: CGPoint(x: 0.5, y: 0.5))
            var steps: [String] = []
            steps.append("\(Int((model.selectedOverlay?.effectiveScale ?? 0) * 100))")
            model.changeSelectedOverlaySize(by: 1)
            model.changeSelectedOverlaySize(by: 1)
            steps.append("\(Int((model.selectedOverlay?.effectiveScale ?? 0) * 100))")
            for _ in 0..<12 {
                model.changeSelectedOverlaySize(by: 1)
            }
            steps.append("\(Int((model.selectedOverlay?.effectiveScale ?? 0) * 100))")
            model.addOverlay(kind: .text, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.1, y: 0.1))
            let newMarkScale = Int((model.selectedOverlay?.effectiveScale ?? 0) * 100)
            model.deleteSelection()
            // Nothing selected: the toolbar's size is for the next mark, and it is kept for the next clip.
            model.selection = nil
            model.tool = .arrow
            model.changeOverlaySize(by: -1)
            model.changeOverlaySize(by: -1)
            let picked = Int(model.shownOverlayScale * 100)
            model.addOverlay(kind: .arrow, start: CGPoint(x: 0.3, y: 0.3), end: CGPoint(x: 0.6, y: 0.6))
            let presetMark = Int((model.selectedOverlay?.effectiveScale ?? 0) * 100)
            let remembered = Int(EditorMemory.videoMarkScale * 100)
            model.deleteSelection()
            model.selection = nil
            model.tool = .blur
            let blurSized = model.canChangeOverlaySize
            model.tearDown()
            EditorMemory.videoMarkScale = 1
            return "arrow % \(steps.joined(separator: "→")) newMark=\(newMarkScale) picked=\(picked) presetMark=\(presetMark) remembered=\(remembered) blurSized=\(blurSized)"

        case "editor-size-test":
            return editorSizeTest()

        default:
            return nil
        }
    }
}
#endif
