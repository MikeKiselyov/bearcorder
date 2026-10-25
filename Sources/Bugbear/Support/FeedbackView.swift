import AppKit
import BugbearCore
import SwiftUI

/// Report a problem with Bugbear or suggest a feature. Shows exactly what will go to GitHub,
/// then opens the filled issue form in the browser.
@MainActor
@Observable
final class FeedbackModel {
    var kind: FeedbackReport.Kind
    var title = ""
    var details = ""
    var includeLogs = true
    /// Crash or error details, filled in when Bugbear offers the report itself.
    var crash = ""
    /// Why the window opened on its own, shown on top.
    var notice = ""
    var errorText = ""
    var isSending = false
    /// Collected when the window opens and when the kind changes, not on every keystroke.
    private(set) var environment: [EnvironmentSnapshot.Field] = []
    private(set) var logLines: [String] = []

    init(kind: FeedbackReport.Kind) {
        self.kind = kind
        refresh()
    }

    /// Counts log loads, so a slower earlier load never replaces a newer one.
    private var loadNumber = 0

    func refresh() {
        environment = Feedback.environment(kind: kind)
        logLines = []
        loadNumber += 1
        let number = loadNumber
        if kind == .problem {
            Task { @MainActor in
                let lines = await Task.detached(priority: .userInitiated) {
                    return Feedback.logTail()
                }.value
                if number == self.loadNumber {
                    self.logLines = lines
                }
            }
        }
    }

    var canSend: Bool {
        if isSending {
            return false
        }
        let hasText = !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCrash = kind == .problem && !crash.isEmpty
        return hasText || hasCrash
    }

    var report: FeedbackReport {
        var lines: [String] = []
        var crashText = ""
        if kind == .problem {
            if includeLogs {
                lines = logLines
            }
            crashText = crash
        }
        return FeedbackReport(kind: kind, title: title, details: details, environment: environment, logLines: lines, crash: crashText)
    }

    func send() {
        isSending = true
        errorText = ""
        let withLogs = includeLogs
        Task { @MainActor in
            var current = self.report
            if current.kind == .problem && withLogs {
                // The newest lines, also when the person sends before the first load finished.
                current.logLines = await Task.detached(priority: .userInitiated) {
                    return Feedback.logTail()
                }.value
            }
            let result = await Feedback.send(current, includeLogs: withLogs)
            self.isSending = false
            if !result.opened {
                self.errorText = "Could not build the GitHub link. Try a shorter description."
                return
            }
            if let warning = result.warning {
                Toast.shared.show(warning, symbol: "exclamationmark.triangle", seconds: 5)
            }
            WindowManager.shared.close(id: "feedback")
        }
    }
}

struct FeedbackView: View {
    @State var model: FeedbackModel
    @State private var showsPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.notice.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                    Text(model.notice)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            PillPicker(options: FeedbackReport.Kind.allCases, selection: $model.kind, label: { kind in
                if kind == .problem {
                    return "Report a problem"
                }
                return "Suggest a feature"
            }, symbol: { kind in
                if kind == .problem {
                    return "ladybug"
                }
                return "lightbulb"
            })
            .frame(width: 360)
            .tip("Problems and ideas go to the Bugbear repository on GitHub as issues")
            .onChange(of: model.kind) { model.refresh() }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(Theme.sectionLabel).foregroundStyle(Theme.textSecondary)
                TextField(titlePlaceholder, text: $model.title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(detailsLabel).font(Theme.sectionLabel).foregroundStyle(Theme.textSecondary)
                TextEditor(text: $model.details)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Theme.well)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderStrong, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(minHeight: 100)
            }

            if model.kind == .problem {
                Toggle("Attach logs", isOn: $model.includeLogs)
                    .tip("Add the last lines of Bugbear's log to the issue and save the full logs as a zip to drag into it")
                if model.includeLogs {
                    Text("A zip with Bugbear's full log and crash reports is saved to \(Feedback.redact(AppSettings.shared.outputFolderPath)) and shown in Finder. Drag it into the issue on GitHub.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DisclosureGroup("What will be sent", isExpanded: $showsPreview) {
                ScrollView {
                    Text(previewText)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 150)
                .background(Theme.well)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .font(.system(size: 13))
            .tip("Your home folder and user name are replaced with ~ and <user>")

            Spacer(minLength: 0)

            if !model.errorText.isEmpty {
                Text(model.errorText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Nothing is sent until you press Submit on GitHub.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Cancel") { WindowManager.shared.close(id: "feedback") }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Open on GitHub") { model.send() }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(!model.canSend)
                    .tip("Open the filled issue form in your browser to check it and submit")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.window)
    }

    private var titlePlaceholder: String {
        if model.kind == .problem {
            return "For example: The saved clip is black"
        }
        return "For example: Blur faces automatically"
    }

    private var detailsLabel: String {
        if model.kind == .problem {
            return "What happened? What did you expect?"
        }
        return "What would you like Bugbear to do?"
    }

    private var previewText: String {
        let report = model.report
        var parts: [String] = []
        parts.append("Title: \(report.title)")
        parts.append(report.details)
        parts.append(report.environmentText)
        if !report.crash.isEmpty {
            parts.append(report.crash)
        }
        if !report.logLines.isEmpty {
            parts.append("Log (up to the last \(report.logLines.count) lines; fewer if the link gets too long):\n" + report.logText)
        }
        if report.kind == .problem && model.includeLogs {
            parts.append("Zip: environment.txt, the full bugbear.log and Bugbear's crash reports from the last 14 days.")
        }
        return parts.joined(separator: "\n\n")
    }
}
