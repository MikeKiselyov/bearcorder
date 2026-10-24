import AppKit
import BugbearCore
import SwiftUI

/// Turns a capture into a Markdown bug report and puts it on the clipboard.
enum BugReportBuilder {
    /// `timeMap` maps source times to the edited video; events in cut parts are dropped.
    @MainActor
    static var preferredFormat: BugReport.Format {
        return BugReport.Format(rawValue: AppSettings.shared.bugReportFormat) ?? .markdown
    }

    static func markdown(for capture: Capture, timeMap: TimeMap?, files: [URL], format: BugReport.Format = .markdown) -> String {
        var actions: [BugReport.Action] = []
        for event in capture.events {
            var time = event.time
            if let map = timeMap {
                if !map.isVisible(source: event.time) { continue }
                time = map.outputTime(forSource: event.time)
            }
            var kind = BugReport.ActionKind.click
            if event.kind == .key {
                kind = .key
            } else if event.kind == .marker {
                kind = .marker
            }
            actions.append(BugReport.Action(kind: kind, time: time, label: event.label, target: event.target ?? "", app: event.app ?? ""))
        }
        var paths: [String] = []
        for file in files {
            paths.append(file.path)
        }
        if FileManager.default.fileExists(atPath: capture.crashReportURL.path) {
            paths.append(capture.crashReportURL.path)
        }
        if FileManager.default.fileExists(atPath: capture.systemLogURL.path) {
            paths.append(capture.systemLogURL.path)
        }
        return BugReport.report(environment: capture.environment, actions: actions, files: paths, format: format)
    }

    /// Copies in `format` and remembers it as the default for next time.
    @MainActor
    static func copy(for capture: Capture, timeMap: TimeMap?, files: [URL], format: BugReport.Format) {
        AppSettings.shared.bugReportFormat = format.rawValue
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown(for: capture, timeMap: timeMap, files: files, format: format), forType: .string)
    }
}

/// "Copy bug report": a click copies in the last used format, the arrow picks Markdown or Jira wiki.
struct CopyReportButton: View {
    var help: String
    var copy: (BugReport.Format) -> Void

    var body: some View {
        Menu {
            ForEach(BugReport.Format.allCases) { format in
                Button("Copy as \(format.rawValue)") { copy(format) }
            }
        } label: {
            Label("Copy bug report · \(BugReportBuilder.preferredFormat.rawValue)", systemImage: "list.number")
                .font(.system(size: 12, weight: .medium))
        } primaryAction: {
            copy(BugReportBuilder.preferredFormat)
        }
        .menuStyle(.button)
        .help(help)
    }
}
