import AppKit
import BugbearCore
import SwiftUI

/// Settings → Bug reports: default format and fields added to every capture.
struct ReportSettingsSection: View {
    @Bindable private var settings = AppSettings.shared

    private let suggestions = ["Stand", "Build", "Test account", "Browser profile", "Feature flag", "Severity"]

    var body: some View {
        Section("Bug reports") {
            Picker("Copy bug report as", selection: $settings.bugReportFormat) {
                ForEach(BugReport.Format.allCases) { format in
                    Text(format.rawValue).tag(format.rawValue)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Your fields")
                Text("Added to every new capture: the environment panel, the badge and the bug report. Empty values are skipped.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(settings.reportFields.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        TextField("Name", text: fieldBinding(index, name: true))
                            .frame(width: 130)
                        TextField("Value", text: fieldBinding(index, name: false))
                        Button {
                            settings.reportFields.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Remove this field")
                    }
                    .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 10) {
                    Button("Add field") {
                        settings.reportFields.append(EnvironmentSnapshot.Field(name: "", value: ""))
                    }
                    ForEach(unusedSuggestions, id: \.self) { name in
                        Button(name) {
                            settings.reportFields.append(EnvironmentSnapshot.Field(name: name, value: ""))
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.link)
                    }
                }
            }
        }
    }

    private var unusedSuggestions: [String] {
        var result: [String] = []
        for name in suggestions where !settings.reportFields.contains(where: { field in field.name == name }) {
            result.append(name)
        }
        return Array(result.prefix(4))
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
                Button("Show in Finder") { NSWorkspace.shared.open(AppPaths.captures) }
            }
            Picker("Delete captures older than", selection: $settings.keepCapturesDays) {
                Text("Never").tag(0)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
            }
            Picker("Keep captures under", selection: $settings.maxCapturesGB) {
                Text("No limit").tag(0)
                Text("2 GB").tag(2)
                Text("5 GB").tag(5)
                Text("10 GB").tag(10)
                Text("20 GB").tag(20)
            }
            HStack {
                Text("Applied after launch and once a day; the oldest go first. Captures open in an editor are kept.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Clean up now") {
                    Task {
                        let deleted = await AppState.shared.cleanUpStorage()
                        resultText = deleted == 1 ? "Deleted 1 capture" : "Deleted \(deleted) captures"
                        await measure()
                    }
                }
                .disabled(settings.keepCapturesDays == 0 && settings.maxCapturesGB == 0)
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
