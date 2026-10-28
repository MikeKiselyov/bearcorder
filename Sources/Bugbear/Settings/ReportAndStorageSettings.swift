import AppKit
import BugbearCore
import SwiftUI

/// Settings → Bug reports: default format, the fields Bugbear fills in and the tester's own fields.
struct ReportSettingsSection: View {
    @Bindable private var settings = AppSettings.shared

    private let suggestions = ["Stand", "Build", "Test account", "Browser profile", "Feature flag", "Severity"]

    var body: some View {
        Section {
            Picker(L("settings.reports.format"), selection: $settings.bugReportFormat) {
                ForEach(BugReport.Format.allCases) { format in
                    Text(format.rawValue).tag(format.rawValue)
                }
            }
            .tip(L("settings.reports.format.tip"))
        }

        Section {
            ForEach(EnvironmentSnapshot.StandardField.allCases, id: \.self) { field in
                HStack(spacing: 10) {
                    Toggle(L("settings.reports.field.include", field.rawValue), isOn: includeBinding(field))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .tip(L("settings.reports.field.include.tip", field.rawValue))
                    TextField("", text: nameBinding(field), prompt: Text(field.rawValue))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .accessibilityLabel(L("settings.reports.field.name.label", field.rawValue))
                        .tip(L("settings.reports.field.name.tip", field.rawValue))
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
            Text(L("settings.reports.standard.header", AppInfo.name))
        } footer: {
            Text(L("settings.reports.standard.footer"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }

        Section {
            if settings.reportFields.isEmpty {
                Text(L("settings.reports.custom.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(settings.reportFields.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField(L("settings.reports.custom.name"), text: fieldBinding(index, name: true))
                        .frame(width: 130)
                        .tip(L("settings.reports.custom.name.tip"))
                    TextField(L("settings.reports.custom.value"), text: fieldBinding(index, name: false))
                        .tip(L("settings.reports.custom.value.tip"))
                    Button {
                        settings.reportFields.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("settings.reports.custom.remove"))
                    .tip(L("settings.reports.custom.remove.tip"))
                }
                .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Button {
                    settings.reportFields.append(EnvironmentSnapshot.Field(name: "", value: ""))
                } label: {
                    Label(L("settings.reports.custom.add"), systemImage: "plus")
                }
                .tip(L("settings.reports.custom.add.tip"))
                if !unusedSuggestions.isEmpty {
                    Text(L("settings.reports.custom.or"))
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
                        .tip(L("settings.reports.custom.suggestion.tip", name))
                    }
                }
            }
        } header: {
            Text(L("settings.reports.custom.header"))
        } footer: {
            Text(L("settings.reports.custom.footer"))
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
            return L("settings.reports.example.app")
        case .url:
            return L("settings.reports.example.url")
        case .locale:
            return Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        case .appearance:
            return L("settings.reports.example.appearance")
        case .time:
            return L("settings.reports.example.time")
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
    @State private var usedText = L("settings.storage.measuring")
    @State private var resultText = ""

    var body: some View {
        Section(L("settings.storage.section")) {
            HStack {
                Text(L("settings.storage.used"))
                Spacer()
                Text(usedText).foregroundStyle(Theme.textSecondary)
                Button(L("settings.storage.showInFinder")) { SystemActions.open(AppPaths.captures) }
                    .tip(L("settings.storage.showInFinder.tip"))
            }
            Picker(L("settings.storage.capturesAge"), selection: $settings.keepCapturesDays) {
                Text(L("settings.storage.never")).tag(0)
                Text(L("settings.storage.days", 7)).tag(7)
                Text(L("settings.storage.days", 30)).tag(30)
                Text(L("settings.storage.days", 90)).tag(90)
            }
            .tip(L("settings.storage.capturesAge.tip"))
            Picker(L("settings.storage.crashClipsAge"), selection: $settings.keepCrashClipsDays) {
                Text(L("settings.storage.days", 3)).tag(3)
                Text(L("settings.storage.days", 7)).tag(7)
                Text(L("settings.storage.days", 30)).tag(30)
                Text(L("settings.storage.never")).tag(0)
            }
            .tip(L("settings.storage.crashClipsAge.tip", AppInfo.name))
            Picker(L("settings.storage.sizeLimit"), selection: $settings.maxCapturesGB) {
                Text(L("settings.storage.sizeLimit.none")).tag(0)
                Text(L("settings.storage.sizeLimit.gigabytes", 2)).tag(2)
                Text(L("settings.storage.sizeLimit.gigabytes", 5)).tag(5)
                Text(L("settings.storage.sizeLimit.gigabytes", 10)).tag(10)
                Text(L("settings.storage.sizeLimit.gigabytes", 20)).tag(20)
            }
            .tip(L("settings.storage.sizeLimit.tip"))
            HStack {
                Text(L("settings.storage.cleanUp.note"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(L("settings.storage.cleanUp")) {
                    Task {
                        let deleted = await AppState.shared.cleanUpStorage()
                        Log.info("clean up now: deleted \(deleted)")
                        resultText = L("settings.storage.cleanUp.deleted", deleted)
                        await measure()
                    }
                }
                .disabled(settings.keepCapturesDays == 0 && settings.maxCapturesGB == 0 && settings.keepCrashClipsDays == 0)
                .tip(L("settings.storage.cleanUp.tip"))
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
        usedText = L("settings.storage.usedValue", DataSizeConverter.describe(Double(total)).decimal, count)
    }
}
