import AppKit
import BugbearCore
import SwiftUI

/// Turns a capture into a Markdown bug report and puts it on the clipboard.
enum BugReportBuilder {
    @MainActor
    static var preferredFormat: BugReport.Format {
        return BugReport.Format(rawValue: AppSettings.shared.bugReportFormat) ?? .markdown
    }

    /// Recorded events as report actions, at the times of the edited video when `timeMap` is given.
    static func actions(for events: [InputEvent], timeMap: TimeMap?) -> [BugReport.Action] {
        var actions: [BugReport.Action] = []
        for event in events {
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
            actions.append(BugReport.Action(kind: kind, time: time, label: event.label, target: event.target ?? "", app: event.app ?? "", text: event.text ?? "", url: event.url ?? ""))
        }
        return actions
    }

    /// `timeMap` maps source times to the edited video; events in cut parts are dropped.
    static func markdown(for capture: Capture, timeMap: TimeMap?, format: BugReport.Format = .markdown) -> String {
        let actions = BugReportBuilder.actions(for: capture.events, timeMap: timeMap)
        return BugReport.report(environment: capture.environment, actions: actions, format: format)
    }

    /// How many steps the report of `capture` has: what Steps to reproduce lists.
    static func stepCount(for capture: Capture, timeMap: TimeMap?) -> Int {
        return BugReport.steps(from: actions(for: capture.events, timeMap: timeMap)).count
    }

    /// Copies in `format` and remembers it as the default for next time.
    @MainActor
    static func copy(for capture: Capture, timeMap: TimeMap?, format: BugReport.Format) {
        AppSettings.shared.bugReportFormat = format.rawValue
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown(for: capture, timeMap: timeMap, format: format), forType: .string)
    }
}

/// "Copy bug report": a click copies in the last used format, the arrow picks Markdown or Jira wiki.
/// Two controls side by side rather than one split menu: the arrow is a pop-up button of its own, with
/// a name VoiceOver reads and items tests can pick without opening the menu.
struct CopyReportButton: View {
    var help: String
    /// Steps the report will have, shown on the button.
    var stepCount: Int
    var copy: (BugReport.Format) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                copy(BugReportBuilder.preferredFormat)
            } label: {
                // Says how many steps the report has before it is pasted; short enough for the side panels.
                Label(L("capture.copyReport.title", stepCount), systemImage: "list.number")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The name stays short and fixed for VoiceOver and the tests; the count is on the button.
            .accessibilityLabel(L("capture.bugReport.copy.accessibility", BugReportBuilder.preferredFormat.rawValue))
            .tip(L("capture.bugReport.copy.tip", help, BugReportBuilder.preferredFormat.rawValue))
            Divider()
                .frame(height: 14)
            Menu {
                ForEach(BugReport.Format.allCases) { format in
                    // The format a click on the button copies in is ticked.
                    if format == BugReportBuilder.preferredFormat {
                        Button(L("capture.bugReport.copyAs", format.rawValue), systemImage: "checkmark") { copy(format) }
                    } else {
                        Button(L("capture.bugReport.copyAs", format.rawValue)) { copy(format) }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Theme.text)
            .frame(width: 26, height: 24)
            .accessibilityLabel(L("capture.bugReport.formatMenu"))
            .tip(L("capture.bugReport.formatMenu.tip"))
        }
        .foregroundStyle(Theme.text)
        .background(Theme.control)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .fixedSize()
    }
}
