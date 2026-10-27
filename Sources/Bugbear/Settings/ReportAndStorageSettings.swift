import AppKit
import BugbearCore
import SwiftUI

/// Settings → Bug reports: default format, the fields Bugbear fills in and the tester's own fields.
struct ReportSettingsSection: View {
    @Bindable private var settings = AppSettings.shared

    private let suggestions = ["Stand", "Build", "Test account", "Browser profile", "Feature flag", "Severity"]

    var body: some View {
        Section {
            Picker("Copy bug report as", selection: $settings.bugReportFormat) {
                ForEach(BugReport.Format.allCases) { format in
                    Text(format.rawValue).tag(format.rawValue)
                }
            }
            .tip("Format used when you copy a bug report from the editor")
        }

        Section {
            ForEach(EnvironmentSnapshot.StandardField.allCases, id: \.self) { field in
                HStack(spacing: 10) {
                    Toggle("Include \(field.rawValue)", isOn: includeBinding(field))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .tip("Put \(field.rawValue) into the panel, the badge and the bug report")
                    TextField("", text: nameBinding(field), prompt: Text(field.rawValue))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .accessibilityLabel("Name for \(field.rawValue)")
                        .tip("The name shown in the panel and the report; clear it to go back to \(field.rawValue)")
                        .disabled(!isIncluded(field))
                    Text(example(field))
                        .font(.system(size: 12))
                        .foregroundStyle(isIncluded(field) ? Theme.textSecondary : Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
        } header: {
            Text("Filled in by \(AppInfo.name)")
        } footer: {
            Text("Collected with every capture. Rename a field or turn it off, and captures you already have show it that way too.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }

        Section {
            if settings.reportFields.isEmpty {
                Text("None yet. Add the stand, build or test account you work with, and every capture gets it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(settings.reportFields.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField("Name", text: fieldBinding(index, name: true))
                        .frame(width: 130)
                        .tip("Field name, for example Stand or Build")
                    TextField("Value", text: fieldBinding(index, name: false))
                        .tip("Field value added to every new capture; leave empty to skip it")
                    Button {
                        settings.reportFields.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove field")
                    .tip("Remove this field")
                }
                .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Button {
                    settings.reportFields.append(EnvironmentSnapshot.Field(name: "", value: ""))
                } label: {
                    Label("New field", systemImage: "plus")
                }
                .tip("Add an empty field: type its name and value")
                if !unusedSuggestions.isEmpty {
                    Text("or")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(unusedSuggestions, id: \.self) { name in
                        Button {
                            settings.reportFields.append(EnvironmentSnapshot.Field(name: name, value: ""))
                        } label: {
                            Text("+ \(name)")
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Theme.control)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.link)
                        .accessibilityLabel(name)
                        .tip("Add a \(name) field, then type its value")
                    }
                }
            }
        } header: {
            Text("Your fields")
        } footer: {
            Text("Added to every new capture: the environment panel, the badge and the bug report. Empty values are skipped.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var unusedSuggestions: [String] {
        var result: [String] = []
        for name in suggestions where !settings.reportFields.contains(where: { field in field.name == name }) {
            result.append(name)
        }
        return Array(result.prefix(4))
    }

    private func isIncluded(_ field: EnvironmentSnapshot.StandardField) -> Bool {
        return !settings.hiddenEnvironmentFields.contains(field.rawValue)
    }

    private func includeBinding(_ field: EnvironmentSnapshot.StandardField) -> Binding<Bool> {
        return Binding(get: {
            return isIncluded(field)
        }, set: { included in
            var hidden = settings.hiddenEnvironmentFields
            hidden.removeAll { name in name == field.rawValue }
            if !included {
                hidden.append(field.rawValue)
            }
            settings.hiddenEnvironmentFields = hidden
        })
    }

    private func nameBinding(_ field: EnvironmentSnapshot.StandardField) -> Binding<String> {
        return Binding(get: {
            return settings.renamedEnvironmentFields[field.rawValue] ?? ""
        }, set: { text in
            // Empty shows the usual name as the placeholder; typing it is not a rename either.
            if text.trimmingCharacters(in: .whitespaces).isEmpty || text == field.rawValue {
                settings.renamedEnvironmentFields[field.rawValue] = nil
            } else {
                settings.renamedEnvironmentFields[field.rawValue] = text
            }
        })
    }

    /// What the field holds, as on this Mac now or as an example when it depends on the capture.
    private func example(_ field: EnvironmentSnapshot.StandardField) -> String {
        switch field {
        case .macOS:
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) (\(EnvironmentCollector.sysctlString("kern.osversion")))"
        case .device:
            return EnvironmentCollector.sysctlString("hw.model")
        case .display:
            return EnvironmentCollector.displayDescription()
        case .app:
            return "The app in front and its version"
        case .url:
            return "The browser tab address"
        case .locale:
            return Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        case .appearance:
            return "Dark or Light"
        case .time:
            return "When the capture was taken"
        }
    }

    private func fieldBinding(_ index: Int, name: Bool) -> Binding<String> {
        return Binding(get: {
            if index >= settings.reportFields.count { return "" }
            if name {
                return settings.reportFields[index].name
            }
            return settings.reportFields[index].value
        }, set: { text in
            if index >= settings.reportFields.count { return }
            if name {
                settings.reportFields[index].name = text
            } else {
                settings.reportFields[index].value = text
            }
        })
    }
}

/// Settings → Storage: space used and automatic clean-up.
struct StorageSettingsSection: View {
    @Bindable private var settings = AppSettings.shared
    @State private var usedText = "Measuring…"
    @State private var resultText = ""

    var body: some View {
        Section("Storage") {
            HStack {
                Text("Captures use")
                Spacer()
                Text(usedText).foregroundStyle(Theme.textSecondary)
                Button("Show in Finder") { SystemActions.open(AppPaths.captures) }
                    .tip("Open the captures folder in Finder")
            }
            Picker("Delete captures older than", selection: $settings.keepCapturesDays) {
                Text("Never").tag(0)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
            }
            .tip("Automatically delete captures older than this")
            Picker("Delete crash clips older than", selection: $settings.keepCrashClipsDays) {
                Text("3 days").tag(3)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("Never").tag(0)
            }
            .tip("Clips \(AppInfo.name) saved by itself when an app crashed, with the crash report")
            Picker("Keep captures under", selection: $settings.maxCapturesGB) {
                Text("No limit").tag(0)
                Text("2 GB").tag(2)
                Text("5 GB").tag(5)
                Text("10 GB").tag(10)
                Text("20 GB").tag(20)
            }
            .tip("Delete the oldest captures when they take more space than this")
            HStack {
                Text("Applied after launch and once a day; the oldest go first. Captures open in an editor are kept.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Clean up now") {
                    Task {
                        let deleted = await AppState.shared.cleanUpStorage()
                        Log.info("clean up now: deleted \(deleted)")
                        resultText = deleted == 1 ? "Deleted 1 capture" : "Deleted \(deleted) captures"
                        await measure()
                    }
                }
                .disabled(settings.keepCapturesDays == 0 && settings.maxCapturesGB == 0 && settings.keepCrashClipsDays == 0)
                .tip("Apply the clean-up rules right now instead of waiting for the daily run")
            }
            if !resultText.isEmpty {
                Text(resultText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .task { await measure() }
    }

    private func measure() async {
        let sizes = await CaptureStore.shared.measureSizes()
        var total: Int64 = 0
        for size in sizes.values {
            total += size
        }
        let count = CaptureStore.shared.captures.count
        usedText = "\(DataSizeConverter.describe(Double(total)).decimal) · \(count) captures"
    }
}
