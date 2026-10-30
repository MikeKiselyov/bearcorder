import AppCore
import Foundation
import XCTest

/// The scripts that send commands to the running app (scripts/dev/app-run.sh, app-command.sh)
/// and the helpers the e2e scripts use. They need the real app to run, so these tests read the script
/// text for the parts that made the round-trip fast; the e2e run exercises the rest.
final class AutomationScriptsTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func text(of relativePath: String) throws -> String {
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The lines of a shell function, from "name() {" to its closing "}" at the start of a line.
    private func body(ofFunction name: String, in script: String) -> String {
        var lines: [String] = []
        var inside = false
        for line in script.components(separatedBy: "\n") {
            if line.hasPrefix("\(name)() {") {
                inside = true
                continue
            }
            if inside && line == "}" {
                break
            }
            if inside {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    func testRunScriptUsesResultFiles() throws {
        let script = try text(of: "scripts/dev/app-run.sh")
        XCTAssertTrue(script.contains("#id="), "the command goes out with a token")
        XCTAssertTrue(script.contains("Application Support/$APP_NAME/automation/results"), "the result is read from the results folder")
        XCTAssertFalse(script.contains("grep -cF \"AUTOMATION"), "the log is no longer searched for the result")
    }

    func testCommandScriptCompilesSender() throws {
        let script = try text(of: "scripts/dev/app-command.sh")
        XCTAssertTrue(script.contains("app-send.swift"), "the sender is built from its source")
        XCTAssertTrue(script.contains("swiftc"))
        XCTAssertTrue(script.contains("osascript"), "osascript stays as the fallback")
        XCTAssertTrue(script.contains("notification=\"$APP_NAME.automation\""), "the same name Automation.notificationName listens for")
        let automation = try text(of: "Sources/App/DevTools/Automation.swift")
        XCTAssertTrue(automation.contains("Notification.Name(\"\\(AppInfo.name).automation\")"), "the app listens for <name>.automation")
        let source = try text(of: "scripts/dev/app-send.swift")
        XCTAssertTrue(source.contains("Notification.Name(arguments[1])"), "the sender posts the name it is given")
        XCTAssertTrue(source.contains("deliverImmediately: true"))
    }

    /// e2e.sh reads results the same way as the other scripts: from the result file, not by
    /// looking for the command's line in the log every second.
    func testEndToEndRunUsesResultFiles() throws {
        let script = try text(of: "scripts/test/e2e.sh")
        let run = body(ofFunction: "run", in: script)
        XCTAssertFalse(run.isEmpty, "run is there")
        XCTAssertTrue(run.contains("scripts/dev/app-run.sh"), "run goes through the result file: \(run)")
        XCTAssertFalse(run.contains("$LOG"), "run does not read the log: \(run)")
    }

    func testPressMenuIsOneCommand() throws {
        let helpers = try text(of: "scripts/test/lib/e2e-helpers.sh")
        let pressMenu = body(ofFunction: "press_menu", in: helpers)
        XCTAssertFalse(pressMenu.isEmpty, "press_menu is there")
        let calls = pressMenu.components(separatedBy: "$R").count - 1
        XCTAssertEqual(calls, 1, "press_menu sends one command: \(pressMenu)")
        XCTAssertTrue(pressMenu.contains("press-menu:"))
    }

    func testFeatureSectionsAreTimed() throws {
        let features = try text(of: "scripts/test/e2e-features.sh")
        XCTAssertFalse(features.contains("echo \"==> "), "sections start with section \"...\" so they are timed")
        XCTAssertTrue(features.contains("print_section_times"))
        let section = try text(of: "scripts/test/e2e-section.sh")
        XCTAssertTrue(section.contains("section \\\"$title\\\""), "e2e-section.sh finds a section by its section line")
    }

    /// A sleep that stays says why: it gives the app real time (a recording, a drag, a window closing)
    /// and no state can be polled for it. Waiting for a state uses wait_for and its siblings instead.
    func testSleepsAreCommented() throws {
        let features = try text(of: "scripts/test/e2e-features.sh")
        let lines = features.components(separatedBy: "\n")
        var uncommented: [String] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || !trimmed.contains("sleep ") {
                continue
            }
            let sameLine = line.contains(" # ")
            var lineAbove = false
            if index > 0 {
                lineAbove = lines[index - 1].trimmingCharacters(in: .whitespaces).hasPrefix("#")
            }
            if !sameLine && !lineAbove {
                uncommented.append("line \(index + 1): \(trimmed)")
            }
        }
        XCTAssertTrue(uncommented.isEmpty, "sleeps without a comment on the line or above it:\n" + uncommented.joined(separator: "\n"))
    }

    /// Runs a snippet with the e2e helpers loaded and returns how it ended.
    private func runWithHelpers(_ snippet: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        let helpers = root.appendingPathComponent("scripts/test/lib/e2e-helpers.sh").path
        process.arguments = ["-c", "R=true; source '\(helpers)'; \(snippet)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    func testWaitHelpersWaitForTheRightThing() throws {
        let marker = NSTemporaryDirectory() + "app-wait-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: marker) }
        // The file appears after about 0.5 s: the wait must see it, and must not return before.
        let appears = try runWithHelpers("(sleep 0.5; touch '\(marker)') & wait_for 5 test -e '\(marker)'; echo $?; test -e '\(marker)' && echo there")
        XCTAssertEqual(appears.output, "0\nthere\n", "wait_for returns 0 once the condition holds: \(appears.output)")
        // A condition that never holds ends in 1 after the timeout, not in 0.
        let never = try runWithHelpers("wait_for 1 test -e '/nonexistent-path'; echo $?")
        XCTAssertEqual(never.output, "1\n")
        let wrongValue = try runWithHelpers("wait_for_value 1 expected echo other; echo $?")
        XCTAssertEqual(wrongValue.output, "1\n", "a different value is not a match")
        let rightValue = try runWithHelpers("wait_for_value 1 expected echo expected; echo $?")
        XCTAssertEqual(rightValue.output, "0\n")
        let text = try runWithHelpers("wait_for_text 1 two echo 'one two three'; echo $?; wait_for_text 1 four echo 'one two three'; echo $?")
        XCTAssertEqual(text.output, "0\n1\n")
        let noText = try runWithHelpers("wait_for_no_text 1 two echo 'one three'; echo $?; wait_for_no_text 1 two echo 'one two'; echo $?")
        XCTAssertEqual(noText.output, "0\n1\n")
    }

    /// The Space waits match a whole window id or control label: "space-confirm" is not the Space
    /// window and "Find projects…" (the row) is not the "Find projects" button of the open list.
    func testExactMatchHelpersIgnoreLongerNames() throws {
        let fakeRun = NSTemporaryDirectory() + "app-fake-run-\(UUID().uuidString).sh"
        defer { try? FileManager.default.removeItem(atPath: fakeRun) }
        try "#!/bin/bash\necho \"$FAKE_ANSWER\"\n".write(toFile: fakeRun, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeRun)
        func ask(_ answer: String, _ check: String) throws -> String {
            try runWithHelpers("R='\(fakeRun)'; FAKE_ANSWER='\(answer)'; export FAKE_ANSWER; \(check); echo $?").output
        }
        XCTAssertEqual(try ask("settings;space-confirm", "window_open space"), "1\n", "a longer id is not the window")
        XCTAssertEqual(try ask("settings;space", "window_open space"), "0\n")
        XCTAssertEqual(try ask("button|Find projects… ;; button|Review App caches", "space_control_shown 'Find projects'"), "1\n", "the row is not the button")
        XCTAssertEqual(try ask("button|Find projects… ;; button|Find projects", "space_control_shown 'Find projects'"), "0\n")
    }

    /// A wait ends about when its timeout says, even when each check is slow (a hung app answers
    /// only after $R's own timeout): counting tries would make 10 slow checks per second of timeout.
    func testWaitHelpersStopAtTheirTimeoutWhenTheCheckIsSlow() throws {
        let helpers = [
            "wait_for 1 eval 'sleep 0.5; false'",
            "wait_for_value 1 expected eval 'sleep 0.5; echo other'",
            "wait_for_text 1 needle eval 'sleep 0.5; echo hay'",
            "wait_for_no_text 1 needle eval 'sleep 0.5; echo needle'",
        ]
        for helper in helpers {
            let started = Date()
            let result = try runWithHelpers("\(helper); echo $?")
            let seconds = Date().timeIntervalSince(started)
            XCTAssertEqual(result.output, "1\n", "\(helper) times out")
            XCTAssertLessThan(seconds, 3.5, "\(helper) took \(seconds) s with a 1 s timeout")
        }
    }

    /// buffer_holds <seconds> holds once the app's buffer-seconds reaches that many; a TIMEOUT or an
    /// empty answer is not enough.
    func testBufferHoldsReadsBufferSeconds() throws {
        let fakeRun = NSTemporaryDirectory() + "app-fake-run-\(UUID().uuidString).sh"
        defer { try? FileManager.default.removeItem(atPath: fakeRun) }
        try "#!/bin/bash\n[ \"$1\" = buffer-seconds ] && echo \"$FAKE_ANSWER\"\n".write(toFile: fakeRun, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeRun)
        func ask(_ answer: String, _ check: String) throws -> String {
            try runWithHelpers("R='\(fakeRun)'; FAKE_ANSWER='\(answer)'; export FAKE_ANSWER; \(check); echo $?").output
        }
        XCTAssertEqual(try ask("5.9", "buffer_holds 6"), "1\n", "5.9 s is less than 6")
        XCTAssertEqual(try ask("6.0", "buffer_holds 6"), "0\n")
        XCTAssertEqual(try ask("31.4", "buffer_holds 31"), "0\n")
        XCTAssertEqual(try ask("TIMEOUT", "buffer_holds 6"), "1\n", "no answer is not a full buffer")
        XCTAssertEqual(try ask("", "buffer_holds 6"), "1\n")
    }

    /// The marker and crash steps in e2e.sh ask for history the buffer must already hold (5 s before
    /// the marker, 30 s before the crash). They wait for it, not for the steps before to take long enough.
    func testEndToEndWaitsForBufferHistory() throws {
        let lines = try text(of: "scripts/test/e2e.sh").components(separatedBy: "\n")
        var markLine: Int?
        var crashReportLine: Int?
        for (index, line) in lines.enumerated() {
            if markLine == nil && line.hasPrefix("run mark ") {
                markLine = index
            }
            if crashReportLine == nil && line.contains("E2E Crasher-test.ips") {
                crashReportLine = index
            }
        }
        func waitsBefore(_ target: Int?, _ wait: String) -> Bool {
            guard let target else { return false }
            for index in max(0, target - 8)..<target where lines[index].hasPrefix("wait_for ") && lines[index].contains(wait) {
                return true
            }
            return false
        }
        XCTAssertTrue(waitsBefore(markLine, "buffer_holds 6"), "e2e.sh waits for 6 s of buffer before the marker")
        XCTAssertTrue(waitsBefore(crashReportLine, "buffer_holds 31"), "e2e.sh waits for 31 s of buffer before the crash report")
    }

    /// open-space opens a new Space window (closing the old one), so "the space window is open" is true
    /// before the page switches. A press or read on the page waits for one of its controls first.
    func testSpacePageWaitsForItsControls() throws {
        let lines = try text(of: "scripts/test/e2e-features.sh").components(separatedBy: "\n")
        let pageUses = ["press_in space", "press:space:", "controls:space", "list_space", "space_controls", "review_controls"]
        var missing: [String] = []
        for (index, line) in lines.enumerated() where line.contains("$R ") && line.contains("open-space") {
            var waited = false
            let last = min(lines.count, index + 12)
            for next in (index + 1)..<last {
                let trimmed = lines[next].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") { continue }
                if trimmed.contains("open-space") { break }
                if trimmed.contains("space_control_shown") {
                    waited = true
                }
                var usesPage = false
                for use in pageUses where trimmed.contains(use) && !trimmed.contains("() {") {
                    usesPage = true
                }
                if usesPage {
                    if !waited {
                        missing.append("e2e-features.sh:\(index + 1) -> \(next + 1): \(trimmed)")
                    }
                    break
                }
            }
        }
        XCTAssertTrue(missing.isEmpty, "Space page used right after open-space without waiting for its controls:\n" + missing.joined(separator: "\n"))
    }

    /// "none" is what the app prints while no area is picked; it must not count as a selection.
    func testPickerSelectedIgnoresNone() throws {
        let fakeRun = NSTemporaryDirectory() + "app-fake-run-\(UUID().uuidString).sh"
        defer { try? FileManager.default.removeItem(atPath: fakeRun) }
        try "#!/bin/bash\necho \"$FAKE_ANSWER\"\n".write(toFile: fakeRun, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeRun)
        let none = try runWithHelpers("R='\(fakeRun)'; FAKE_ANSWER=none; export FAKE_ANSWER; picker_selected; echo $?")
        XCTAssertEqual(none.output, "1\n", "none is not a selection")
        let empty = try runWithHelpers("R='\(fakeRun)'; FAKE_ANSWER=''; export FAKE_ANSWER; picker_selected; echo $?")
        XCTAssertEqual(empty.output, "1\n", "nothing is not a selection")
        let area = try runWithHelpers("R='\(fakeRun)'; FAKE_ANSWER='10,20,640,360'; export FAKE_ANSWER; picker_selected; echo $?")
        XCTAssertEqual(area.output, "0\n")
    }

    /// Runs app-run.sh from a copy of the scripts with a made-up sender that writes `result` as the
    /// app does, under a temporary home. Returns what the script printed.
    private func runScriptOutput(result: String) throws -> String {
        let fake = FileManager.default.temporaryDirectory.appendingPathComponent("app-run-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fake) }
        let dev = fake.appendingPathComponent("scripts/dev", isDirectory: true)
        let lib = fake.appendingPathComponent("scripts/lib", isDirectory: true)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("scripts/dev/app-run.sh"), to: dev.appendingPathComponent("app-run.sh"))
        try FileManager.default.copyItem(at: root.appendingPathComponent("scripts/lib/common.sh"), to: lib.appendingPathComponent("common.sh"))
        try FileManager.default.copyItem(at: root.appendingPathComponent("scripts/lib/app-name.sh"), to: lib.appendingPathComponent("app-name.sh"))
        let support = fake.appendingPathComponent("Sources/AppCore/Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("Sources/AppCore/Support/AppInfo.swift"), to: support.appendingPathComponent("AppInfo.swift"))
        // The sender takes "<command> #id=<token>" and the app writes the result file named by the token.
        let sender = """
        #!/bin/bash
        token="${1##*#id=}"
        folder="$HOME/Library/Application Support/\(AppInfo.name)/automation/results"
        mkdir -p "$folder"
        printf '%s' "$FAKE_RESULT" > "$folder/$token"
        """
        let senderURL = dev.appendingPathComponent("app-command.sh")
        try sender.write(to: senderURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: senderURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [dev.appendingPathComponent("app-run.sh").path, "screens", "5"]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = fake.appendingPathComponent("home").path
        environment["FAKE_RESULT"] = result
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// The result is one line ending in a newline, as the log path printed it: `$R screens | wc -l`
    /// counts every display, and the last one is not lost to a missing newline.
    func testRunScriptPrintsResultWithNewline() throws {
        XCTAssertEqual(try runScriptOutput(result: "1,0,0,1440,900;2,1440,0,1920,1080"), "1,0,0,1440,900;2,1440,0,1920,1080\n")
        XCTAssertEqual(try runScriptOutput(result: "ok\n"), "ok\n", "a result that has a newline gets no second one")
    }

    /// press-now and choose-now answer before the window has redrawn, so the script waits for what
    /// they did (a setting, the clipboard, a recorded action) right after: a wait helper within the
    /// next few lines, not a read that could see the state from before.
    func testPressNowIsFollowedByAWait() throws {
        let folders = ["scripts/test", "scripts/test/lib"]
        let waits = ["wait_for ", "wait_for_value ", "wait_for_text ", "wait_for_no_text "]
        var missing: [String] = []
        var uses = 0
        for folder in folders {
            let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)
            for file in files.sorted() where file.hasSuffix(".sh") {
                var lines: [String] = []
                for line in try text(of: "\(folder)/\(file)").components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.hasPrefix("#") {
                        lines.append(trimmed)
                    }
                }
                for (index, line) in lines.enumerated() {
                    let pressesNow = line.hasPrefix("press_now ") || line.contains("press-now:") || line.contains("choose-now:")
                    // The helper's own definition is not a call.
                    if !pressesNow || line.hasPrefix("press_now() {") { continue }
                    uses += 1
                    var waited = false
                    for next in lines[(index + 1)..<min(lines.count, index + 7)] {
                        for wait in waits where next.hasPrefix(wait) {
                            waited = true
                        }
                    }
                    if !waited {
                        missing.append("\(folder)/\(file): \(line)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(uses, 0, "press_now is used somewhere")
        XCTAssertTrue(missing.isEmpty, "press-now or choose-now without a wait after it:\n" + missing.joined(separator: "\n"))
    }

    /// Every wait helper call gives its timeout first. Without it the condition's name is taken for the
    /// timeout and, under set -u, the whole script stops ("unbound variable").
    func testWaitHelperCallsStartWithTimeout() throws {
        let folders = ["scripts/test", "scripts/test/lib"]
        let helpers: Set<String> = ["wait_for", "wait_for_value", "wait_for_text", "wait_for_no_text"]
        var missing: [String] = []
        for folder in folders {
            let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)
            for file in files.sorted() where file.hasSuffix(".sh") {
                let script = try text(of: "\(folder)/\(file)")
                for (index, line) in script.components(separatedBy: "\n").enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("#") { continue }
                    let words = trimmed.components(separatedBy: CharacterSet(charactersIn: " ;&|(!\t"))
                    for (position, word) in words.enumerated() where helpers.contains(word) {
                        var timeout = ""
                        if position + 1 < words.count {
                            timeout = words[position + 1]
                        }
                        // "wait_for() {" is the definition, not a call.
                        if timeout.hasPrefix(")") { continue }
                        if Int(timeout) == nil {
                            missing.append("\(folder)/\(file):\(index + 1): \(trimmed)")
                        }
                    }
                }
            }
        }
        XCTAssertTrue(missing.isEmpty, "wait helper calls without a timeout:\n" + missing.joined(separator: "\n"))
    }
}
