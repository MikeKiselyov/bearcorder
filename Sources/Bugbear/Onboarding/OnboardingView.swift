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
                .accessibilityLabel("Step \(page + 1) of \(pageCount)")
                Spacer()
                if page > 0 {
                    Button("Back") { page -= 1 }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Skip") { complete() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.trailing, 8)
                }
                Button(page == pageCount - 1 ? "Start using \(AppInfo.name)" : "Continue") {
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
                    Text("Welcome to \(AppInfo.name)").font(.system(size: 26, weight: .bold))
                    Text("Catch the bug that already happened.").font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                }
            }
            feature("gobackward", "Rolling screen buffer", "The last minutes of your screen are always kept. Saw a bug? Save what just happened, no need to reproduce it.")
            feature("record.circle", "Record with pause and drawing", "Record a screen, all screens or an area. Pause, draw arrows on the screen, add your camera and voice.")
            feature("pencil.and.outline", "Mark up and send", "Arrows, boxes, steps and blur on screenshots and videos. The environment (OS, app, URL) is added for you.")
            feature("wrench.and.screwdriver", "Dev toolbox", "Format JSON and XML, decode JWT, convert timestamps and time zones, generate UUIDs.")
            Text("Everything stays on your Mac. Nothing is uploaded.")
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
            Text("Saw a bug? It's already recorded.").font(.system(size: 24, weight: .bold))
            Text("You know the moment: the page flickers, an error flashes for a second, a button does something odd. You try again and it never happens twice.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            BufferTimeline()
            Text("With the screen buffer on, \(AppInfo.name) quietly keeps the last few minutes. Press \(HotKeySettings.shared.readable(for: .saveShort)) and the moment you missed opens in the editor: trim it, add an arrow, paste it into the ticket. It also saves the minute before an app crashes, by itself.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                bufferChoice(
                    on: true,
                    symbol: "gobackward",
                    title: "Keep the last minutes",
                    text: "A small ring next to the bear shows it is on. Stays on this Mac, deleted when the app quits."
                )
                bufferChoice(
                    on: false,
                    symbol: "pause.circle",
                    title: "Off for now",
                    text: "Nothing runs in the background. Screenshots, recordings and the toolbox work as usual."
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            ScreenCaptureIndicatorNote()
            if settings.startBufferOnLaunch && NSScreen.screens.count > 1 {
                Toggle(isOn: $settings.captureAllDisplays) {
                    Text("Keep all \(NSScreen.screens.count) screens, so a bug on any of them is saved. Pick the screen in the editor.")
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
            }
            HStack(spacing: 12) {
                if settings.startBufferOnLaunch {
                    Text("Keep the last").font(.system(size: 13))
                    Picker(selection: $settings.bufferMinutes) {
                        Text("1 min").tag(1)
                        Text("2 min").tag(2)
                        Text("3 min").tag(3)
                        Text("5 min").tag(5)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                Spacer()
                Text("Change it any time in Settings → Buffer.")
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
            Text("How it works").font(.system(size: 24, weight: .bold))
            VStack(alignment: .leading, spacing: 12) {
                howStep(1, "A ring next to the bear means the buffer is on", "It keeps the last minutes of the screen. Turn it on or off in the menu that opens from the bear.")
                howStep(2, "Saw a bug? Press \(keys.readable(for: .saveShort))", "The last 30 seconds open in the editor. \(keys.readable(for: .saveMinute)) saves a minute, \(keys.readable(for: .saveBuffer)) the whole buffer. The same buttons are in the menu.")
                howStep(3, "Something about to happen? Press \(keys.readable(for: .mark))", "It marks the moment; the next save reaches back to it.")
                howStep(4, "Trim, point, share", "In the editor cut the clip, add arrows and text, then copy it or drag it into the ticket.")
                howStep(5, "Stopped it from the macOS menu?", "Stop in the purple screen recording icon saves what the buffer holds and offers to open it.")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Save files to").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.textSecondary)
                    Text(displayPath(app.settings.outputFolderPath))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseOutputFolder() }
                        .buttonStyle(SecondaryButtonStyle())
                        .tip("Pick the folder where saved screenshots and clips go")
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Theme.control)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Change it any time in Settings.")
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
                Text("Save the minute before an app crashes").font(.system(size: 14, weight: .semibold))
            }
            .toggleStyle(.checkbox)
            .tip("When an app you worked with crashes, \(AppInfo.name) saves the last minute of the screen with the crash report")
            if settings.saveOnCrash {
                HStack(spacing: 10) {
                    Text("Keep crash clips for").font(.system(size: 13))
                    Picker(selection: $settings.keepCrashClipsDays) {
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("Always").tag(0)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .tip("After this they are deleted. Clips you open in the editor stay while open")
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
        if let url = SystemActions.chooseFolder(startingAt: app.settings.outputFolder, prompt: "Save here") {
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
            Text("Permissions").font(.system(size: 24, weight: .bold))
            Text("Only Screen Recording is required. The rest turn on extras and can be granted later in Settings.")
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
            Text("Shortcuts").font(.system(size: 24, weight: .bold))
            Text("They work from any app. Everything is also in the menu bar.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                shortcut(.saveMinute, "Save the last minute of the screen", "\(keys.readable(for: .saveShort)) for 30 s, \(keys.readable(for: .saveBuffer)) for the whole buffer")
                shortcut(.mark, "Mark the moment", "The next save reaches back to it and opens there")
                shortcut(.screenshotArea, "Screenshot an area", "\(keys.readable(for: .screenshotWindow)) for a window, \(keys.readable(for: .copyText)) copies the text in an area")
                shortcut(.recordToggle, "Start or stop a recording", "\(keys.readable(for: .recordPause)) pauses and resumes")
                shortcut(.draw, "Draw on the screen", "Arrows and boxes appear in the video")
                shortcut(.camera, "Camera bubble", "Drag it, scroll to resize")
                shortcut(.toolbox, "Dev toolbox", "Opens with what is on your clipboard")
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
                Text("\(title) (\(keys.spoken(for: action)))").font(.system(size: 13, weight: .semibold))
                Text(hint).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("You're set").font(.system(size: 24, weight: .bold))
            HStack(spacing: 14) {
                Image(nsImage: Logo.menuBarImage(recording: true))
                    .renderingMode(.template)
                    .foregroundStyle(Theme.text)
                    .padding(10)
                    .background(Theme.control)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("\(AppInfo.name) lives in the menu bar, top right. Click the bear to save from the buffer, take screenshots, record, or open the toolbox.")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Try it now")
                if app.settings.startBufferOnLaunch {
                    tryStep("1", "Click around in any app for a few seconds.")
                    tryStep("2", "Press \(HotKeySettings.shared.readable(for: .saveShort)): the last 30 seconds open in the video editor.")
                    tryStep("3", "Add an arrow, then Copy and paste it into a ticket.")
                } else {
                    tryStep("1", "Press \(HotKeySettings.shared.readable(for: .screenshotArea)) and drag over any part of the screen.")
                    tryStep("2", "The screenshot opens in the editor: add an arrow or a box.")
                    tryStep("3", "Press ⌘C (Command + C) and paste it into a ticket.")
                }
            }
            if !screenAccess && app.settings.startBufferOnLaunch {
                Label("Screen Recording is not allowed yet, so the buffer cannot start. Go back to Permissions to allow it.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("You can open this guide again from Settings.")
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
                Text("\(HotKeySettings.shared.readable(for: .saveShort)) saves this part")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentSoft)
                Text("now").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.accentSoft)
            }
        }
        .padding(12)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A timeline of the last three minutes. The bug happened shortly before now, and the shortcut saves that part.")
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
            Text("While the buffer or a recording runs, macOS shows this purple icon in the menu bar. That's normal: it only means the screen is being captured, and nothing leaves your Mac.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .tip("The purple icon is macOS's own sign that an app captures the screen. Apps cannot hide it.")
    }
}

/// What a permission is used for, shown as small examples under it in the welcome guide.
struct PermissionUse: Identifiable, Equatable {
    var symbol: String
    var text: String
    var id: String { text }

    static let screen = [
        PermissionUse(symbol: "gobackward.30", text: "⌥⇧1: the last 30 s"),
        PermissionUse(symbol: "camera.viewfinder", text: "Screenshots"),
        PermissionUse(symbol: "record.circle", text: "Recordings"),
        PermissionUse(symbol: "text.viewfinder", text: "Text from screen"),
    ]
    static let accessibility = [
        PermissionUse(symbol: "list.number", text: "Click “Sign in” in steps"),
        PermissionUse(symbol: "command", text: "⌘C in clips"),
        PermissionUse(symbol: "arrow.down.to.line", text: "Scrolling shots"),
        PermissionUse(symbol: "macwindow", text: "Window sizes"),
    ]
    static let microphone = [
        PermissionUse(symbol: "waveform", text: "Your voice in clips"),
    ]
    static let camera = [
        PermissionUse(symbol: "person.crop.circle", text: "Your face in a bubble"),
    ]
    static let browsers = [
        PermissionUse(symbol: "link", text: "URL in reports"),
        PermissionUse(symbol: "list.number", text: "Open shop.test/login in steps"),
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
