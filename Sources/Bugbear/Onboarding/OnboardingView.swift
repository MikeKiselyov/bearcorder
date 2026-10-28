import AVFoundation
import AppKit
import SwiftUI
import BugbearCore

/// First-launch guide: what the app does, whether to keep a screen buffer, permissions, shortcuts,
/// where to find it.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State private var page = 0
    @State private var screenAccess = ScreenBuffer.hasScreenRecordingAccess

    private let pageCount = 6
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    static let completedKey = "onboardingCompleted"
    /// The step the guide was on, so it comes back there after a relaunch (Screen Recording only
    /// takes effect after one) or when it was closed halfway.
    static let pageKey = "onboardingPage"
    private static let permissionsPage = 3

    /// `startPage` nil: the saved step, or the first one.
    init(startPage: Int? = nil) {
        var initial = startPage ?? UserDefaults.standard.integer(forKey: OnboardingView.pageKey)
        if initial < 0 || initial > 5 {
            initial = 0
        }
        _page = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: buffer
                case 2: howItWorks
                case 3: permissions
                case 4: shortcuts
                default: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36)
            .padding(.top, 48)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.text : Theme.borderStrong)
                            .frame(width: index == page ? 18 : 7, height: 7)
                    }
                }
                .accessibilityLabel(L("onboarding.stepOf", page + 1, pageCount))
                Spacer()
                if page > 0 {
                    Button(L("onboarding.button.back")) { page -= 1 }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button(L("onboarding.button.skip")) { complete() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.trailing, 8)
                }
                Button(page == pageCount - 1 ? L("onboarding.button.start", AppInfo.name) : L("onboarding.button.continue")) {
                    if page == pageCount - 1 {
                        complete()
                    } else {
                        page += 1
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 20)
            .background(Theme.sidebar)
        }
        .foregroundStyle(Theme.text)
        .auroraBackground()
        .onReceive(ticker) { _ in refreshPermissions() }
        .onChange(of: page) { _, newPage in
            UserDefaults.standard.set(newPage, forKey: OnboardingView.pageKey)
        }
    }

    private func refreshPermissions() {
        screenAccess = ScreenBuffer.hasScreenRecordingAccess
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: OnboardingView.completedKey)
        UserDefaults.standard.removeObject(forKey: OnboardingView.pageKey)
        // Saved even when left at the default, so it is the person's choice from now on.
        UserDefaults.standard.set(app.settings.keepCrashClipsDays, forKey: "keepCrashClipsDays")
        WindowManager.shared.close(id: "onboarding")
        if app.settings.startBufferOnLaunch {
            if app.bufferState != .running && ScreenBuffer.hasScreenRecordingAccess {
                Task { await app.startBuffer() }
            }
        } else if app.bufferState == .running {
            Task { await app.pauseBuffer() }
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                LogoView(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("onboarding.welcome.title", AppInfo.name)).font(.system(size: 26, weight: .bold))
                    Text(L("onboarding.welcome.subtitle")).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                }
            }
            feature("gobackward", L("onboarding.welcome.buffer.title"), L("onboarding.welcome.buffer.text"))
            feature("record.circle", L("onboarding.welcome.record.title"), L("onboarding.welcome.record.text"))
            feature("pencil.and.outline", L("onboarding.welcome.markup.title"), L("onboarding.welcome.markup.text"))
            feature("wrench.and.screwdriver", L("onboarding.welcome.toolbox.title"), L("onboarding.welcome.toolbox.text"))
            Text(L("onboarding.welcome.local"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Theme.accentSoft)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The buffer is the one feature that runs all the time, so the person decides on it up front.
    private var buffer: some View {
        @Bindable var settings = app.settings
        return VStack(alignment: .leading, spacing: 14) {
            Text(L("onboarding.buffer.title")).font(.system(size: 24, weight: .bold))
            Text(L("onboarding.buffer.story"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            BufferTimeline()
            Text(L("onboarding.buffer.explain", AppInfo.name, HotKeySettings.shared.readable(for: .saveShort)))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                bufferChoice(
                    on: true,
                    symbol: "gobackward",
                    title: L("onboarding.buffer.on.title"),
                    text: L("onboarding.buffer.on.text")
                )
                bufferChoice(
                    on: false,
                    symbol: "pause.circle",
                    title: L("onboarding.buffer.off.title"),
                    text: L("onboarding.buffer.off.text")
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            ScreenCaptureIndicatorNote()
            if settings.startBufferOnLaunch && NSScreen.screens.count > 1 {
                Toggle(isOn: $settings.captureAllDisplays) {
                    Text(L("onboarding.buffer.allDisplays", NSScreen.screens.count))
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
            }
            HStack(spacing: 12) {
                if settings.startBufferOnLaunch {
                    Text(L("onboarding.buffer.keepLast")).font(.system(size: 13))
                    Picker(selection: $settings.bufferMinutes) {
                        Text(L("onboarding.buffer.minutes1")).tag(1)
                        Text(L("onboarding.buffer.minutes2")).tag(2)
                        Text(L("onboarding.buffer.minutes3")).tag(3)
                        Text(L("onboarding.buffer.minutes5")).tag(5)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                Spacer()
                Text(L("onboarding.buffer.changeLater"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(height: 24)
        }
    }

    /// How saving from the buffer works, step by step, and where files go.
    private var howItWorks: some View {
        let keys = HotKeySettings.shared
        return VStack(alignment: .leading, spacing: 14) {
            Text(L("onboarding.how.title")).font(.system(size: 24, weight: .bold))
            VStack(alignment: .leading, spacing: 12) {
                howStep(1, L("onboarding.how.step1.title"), L("onboarding.how.step1.text"))
                howStep(2, L("onboarding.how.step2.title", keys.readable(for: .saveShort)), L("onboarding.how.step2.text", keys.readable(for: .saveMinute), keys.readable(for: .saveBuffer)))
                howStep(3, L("onboarding.how.step3.title", keys.readable(for: .mark)), L("onboarding.how.step3.text"))
                howStep(4, L("onboarding.how.step4.title"), L("onboarding.how.step4.text"))
                howStep(5, L("onboarding.how.step5.title"), L("onboarding.how.step5.text"))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("onboarding.folder.title")).font(.system(size: 14, weight: .semibold))
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.textSecondary)
                    Text(displayPath(app.settings.outputFolderPath))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L("onboarding.folder.choose")) { chooseOutputFolder() }
                        .buttonStyle(SecondaryButtonStyle())
                        .tip(L("onboarding.folder.choose.tip"))
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Theme.control)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(L("onboarding.folder.changeLater"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            crashClips
        }
    }

    /// The minute before an app crashed is saved by itself; how long those clips stay.
    private var crashClips: some View {
        @Bindable var settings = app.settings
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $settings.saveOnCrash) {
                Text(L("onboarding.crash.toggle")).font(.system(size: 14, weight: .semibold))
            }
            .toggleStyle(.checkbox)
            .tip(L("onboarding.crash.toggle.tip", AppInfo.name))
            if settings.saveOnCrash {
                HStack(spacing: 10) {
                    Text(L("onboarding.crash.keepFor")).font(.system(size: 13))
                    Picker(selection: $settings.keepCrashClipsDays) {
                        Text(L("onboarding.crash.days3")).tag(3)
                        Text(L("onboarding.crash.days7")).tag(7)
                        Text(L("onboarding.crash.days30")).tag(30)
                        Text(L("onboarding.crash.always")).tag(0)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .tip(L("onboarding.crash.keepFor.tip"))
                }
            }
        }
    }

    private func howStep(_ number: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Theme.accent.opacity(0.2))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "~/Desktop/Bugbear" instead of the full home path.
    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func chooseOutputFolder() {
        if let url = SystemActions.chooseFolder(startingAt: app.settings.outputFolder, prompt: L("onboarding.folder.choose.prompt")) {
            app.settings.outputFolderPath = url.path
        }
    }

    private func bufferChoice(on: Bool, symbol: String, title: String, text: String) -> some View {
        let selected = app.settings.startBufferOnLaunch == on
        return Button {
            app.settings.startBufferOnLaunch = on
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 16))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
                }
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var permissions: some View {
        @Bindable var settings = app.settings
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("onboarding.permissions.title")).font(.system(size: 24, weight: .bold))
            Text(L("onboarding.permissions.intro"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PermissionsList(relaunch: { relaunch() })
            TypedTextChoice(isOn: $settings.recordTypedText)
                .onChange(of: settings.recordTypedText) { app.applyStepPrivacy() }
        }
    }

    private var shortcuts: some View {
        let keys = HotKeySettings.shared
        return VStack(alignment: .leading, spacing: 14) {
            Text(L("onboarding.shortcuts.title")).font(.system(size: 24, weight: .bold))
            Text(L("onboarding.shortcuts.intro"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                shortcut(.saveMinute, L("onboarding.shortcuts.saveMinute.title"), L("onboarding.shortcuts.saveMinute.hint", keys.readable(for: .saveShort), keys.readable(for: .saveBuffer)))
                shortcut(.mark, L("onboarding.shortcuts.mark.title"), L("onboarding.shortcuts.mark.hint"))
                shortcut(.screenshotArea, L("onboarding.shortcuts.screenshot.title"), L("onboarding.shortcuts.screenshot.hint", keys.readable(for: .screenshotWindow), keys.readable(for: .copyText)))
                shortcut(.recordToggle, L("onboarding.shortcuts.record.title"), L("onboarding.shortcuts.record.hint", keys.readable(for: .recordPause)))
                shortcut(.draw, L("onboarding.shortcuts.draw.title"), L("onboarding.shortcuts.draw.hint"))
                shortcut(.camera, L("onboarding.shortcuts.camera.title"), L("onboarding.shortcuts.camera.hint"))
                shortcut(.toolbox, L("onboarding.shortcuts.toolbox.title"), L("onboarding.shortcuts.toolbox.hint"))
            }
        }
    }

    /// The keys as symbols in a key cap, and in words next to the title.
    private func shortcut(_ action: HotKeyAction, _ title: String, _ hint: String) -> some View {
        let keys = HotKeySettings.shared
        return GridRow {
            Text(keys.text(for: action))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.control)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(L("onboarding.shortcuts.row", title, keys.spoken(for: action))).font(.system(size: 13, weight: .semibold))
                Text(hint).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("onboarding.finish.title")).font(.system(size: 24, weight: .bold))
            HStack(spacing: 14) {
                Image(nsImage: Logo.menuBarImage(recording: true))
                    .renderingMode(.template)
                    .foregroundStyle(Theme.text)
                    .padding(10)
                    .background(Theme.control)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(L("onboarding.finish.menuBar", AppInfo.name))
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(L("onboarding.finish.try"))
                if app.settings.startBufferOnLaunch {
                    tryStep("1", L("onboarding.finish.buffer.step1"))
                    tryStep("2", L("onboarding.finish.buffer.step2", HotKeySettings.shared.readable(for: .saveShort)))
                    tryStep("3", L("onboarding.finish.buffer.step3"))
                } else {
                    tryStep("1", L("onboarding.finish.screenshot.step1", HotKeySettings.shared.readable(for: .screenshotArea)))
                    tryStep("2", L("onboarding.finish.screenshot.step2"))
                    tryStep("3", L("onboarding.finish.screenshot.step3"))
                }
            }
            if !screenAccess && app.settings.startBufferOnLaunch {
                Label(L("onboarding.finish.noScreenAccess"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("onboarding.finish.reopen"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func tryStep(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 22, height: 22)
                .background(Theme.accent)
                .clipShape(Circle())
            Text(text).font(.system(size: 13))
        }
    }

    private func relaunch() {
        if SystemActions.recordInstead("relaunch") { return }
        // Back on the Permissions step after the restart, with Screen Recording now allowed.
        UserDefaults.standard.set(OnboardingView.permissionsPage, forKey: OnboardingView.pageKey)
        Relaunch.now()
    }
}

/// The last minutes of the screen as bars: the bug happened a little while ago, and ⌥⇧1 takes the
/// last 30 seconds that hold it.
private struct BufferTimeline: View {
    private let heights: [CGFloat] = [0.35, 0.5, 0.3, 0.55, 0.4, 0.45, 0.3, 0.6, 0.5, 0.35, 0.5, 0.4, 0.55, 0.45, 0.9, 1.0, 0.7, 0.5, 0.6, 0.45]
    /// Bars from here on are the saved part.
    private let savedFrom = 12
    private let bugAt = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<heights.count, id: \.self) { index in
                    VStack(spacing: 3) {
                        if index == bugAt {
                            Image(systemName: "ladybug.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.accent)
                        }
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index >= savedFrom ? Theme.accent : Theme.borderStrong)
                            .frame(height: 34 * heights[index])
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 54, alignment: .bottom)
            HStack {
                Text("−3:00").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(L("onboarding.timeline.saves", HotKeySettings.shared.readable(for: .saveShort)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentSoft)
                Text(L("onboarding.timeline.now")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.accentSoft)
            }
        }
        .padding(12)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("onboarding.timeline.accessibility"))
    }
}

/// macOS shows a purple icon in the menu bar whenever an app captures the screen. People who see it
/// for the first time may think something is spying on them, so the guide shows it and says why.
struct ScreenCaptureIndicatorNote: View {
    var body: some View {
        HStack(spacing: 12) {
            // Drawn like the system's own indicator: a purple capsule with a screen and a person.
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 24)
                .background(Capsule().fill(Color(hex: 0x6E5BE8)))
                .accessibilityHidden(true)
            Text(L("onboarding.indicator.text"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .tip(L("onboarding.indicator.tip"))
    }
}

/// What a permission is used for, shown as small examples under it in the welcome guide.
struct PermissionUse: Identifiable, Equatable {
    var symbol: String
    var text: String
    var id: String { text }

    static let screen = [
        PermissionUse(symbol: "gobackward.30", text: L("permissions.use.screen.lastSeconds")),
        PermissionUse(symbol: "camera.viewfinder", text: L("permissions.use.screen.screenshots")),
        PermissionUse(symbol: "record.circle", text: L("permissions.use.screen.recordings")),
        PermissionUse(symbol: "text.viewfinder", text: L("permissions.use.screen.text")),
    ]
    static let accessibility = [
        PermissionUse(symbol: "list.number", text: L("permissions.use.accessibility.steps")),
        PermissionUse(symbol: "command", text: L("permissions.use.accessibility.keys")),
        PermissionUse(symbol: "arrow.down.to.line", text: L("permissions.use.accessibility.scrolling")),
        PermissionUse(symbol: "macwindow", text: L("permissions.use.accessibility.windows")),
    ]
    static let microphone = [
        PermissionUse(symbol: "waveform", text: L("permissions.use.microphone.voice")),
    ]
    static let camera = [
        PermissionUse(symbol: "person.crop.circle", text: L("permissions.use.camera.face")),
    ]
    static let browsers = [
        PermissionUse(symbol: "link", text: L("permissions.use.browsers.url")),
        PermissionUse(symbol: "list.number", text: L("permissions.use.browsers.steps")),
    ]
}

struct PermissionUses: View {
    var uses: [PermissionUse]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(uses) { use in
                HStack(spacing: 4) {
                    Image(systemName: use.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accentSoft)
                    Text(use.text)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.control)
                .clipShape(Capsule())
            }
        }
    }
}
