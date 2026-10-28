import AppKit
import BugbearCore
import SwiftUI

/// Floating control bar shown while recording: timer, pause, draw tools, stop.
struct RecordingHUDView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var overlay = app.overlay
        HStack(spacing: 8) {
            if let session = app.recording {
                RecordingClock(session: session)
                    .frame(width: RecordingClockView.width, height: 18, alignment: .leading)

                HUDButton(systemImage: session.isPaused ? "play.fill" : "pause.fill", help: session.isPaused ? L("recording.hud.resume", HotKeySettings.shared.text(for: .recordPause)) : L("recording.hud.pause", HotKeySettings.shared.text(for: .recordPause))) {
                    session.togglePause()
                }
            } else {
                Text(L("recording.hud.drawOnScreen"))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.leading, 4)
            }

            divider

            HUDButton(systemImage: "pencil.and.scribble", help: overlay.isDrawing ? L("recording.hud.draw.stop") : L("recording.hud.draw.start", HotKeySettings.shared.text(for: .draw)), isSelected: overlay.isDrawing) {
                app.toggleDrawing()
            }

            if overlay.isDrawing {
                ForEach(LiveOverlay.liveTools) { tool in
                    HUDButton(systemImage: tool.symbol, help: tool.title, isSelected: overlay.tool == tool) {
                        overlay.tool = tool
                    }
                }
                divider
                ForEach([AnnotationColor.coral, .yellow, .blue, .green, .purple, .white]) { color in
                    Button {
                        overlay.color = color
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.white, lineWidth: overlay.color == color ? 2 : 0))
                            .frame(width: 22, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.rawValue)
                    .tip(L("recording.hud.color", color.rawValue))
                }
                divider
                HUDButton(systemImage: overlay.autoFade ? "timer" : "pin.fill", help: overlay.autoFade ? L("recording.hud.marksFade") : L("recording.hud.marksStay")) {
                    overlay.autoFade.toggle()
                }
                HUDButton(systemImage: "arrow.uturn.backward", help: L("recording.hud.undo")) {
                    overlay.undo()
                }
                HUDButton(systemImage: "trash", help: L("recording.hud.clear")) {
                    overlay.clear()
                }
            }

            divider

            if app.recording != nil {
                HUDButton(systemImage: "xmark", help: L("recording.hud.discard")) {
                    app.discardRecording()
                }
                Button {
                    Task { await app.stopRecording() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill").font(.system(size: 10))
                        Text(L("recording.hud.stop")).font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .tip(L("recording.hud.stop.tip", HotKeySettings.shared.text(for: .recordToggle)))
            } else {
                HUDButton(systemImage: "xmark", help: L("recording.hud.closeDrawingBar")) {
                    app.hideOverlay()
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .foregroundStyle(Theme.text)
        .background(Color(hex: 0x1C1D20, alpha: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderStrong, lineWidth: 1))
        .fixedSize()
        .preferredColorScheme(.dark)
    }

    private var divider: some View {
        Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 22).padding(.horizontal, 2)
    }
}

/// The dot, "REC" or "Paused" and the time. Drawn by AppKit and redrawn on its own: a SwiftUI
/// timeline re-laid out the whole HUD window four times a second, about 10% CPU while recording.
struct RecordingClock: NSViewRepresentable {
    let session: RecordingSession

    func makeNSView(context: Context) -> RecordingClockView {
        return RecordingClockView(session: session)
    }

    func updateNSView(_ view: RecordingClockView, context: Context) {
        if view.session !== session {
            view.session = session
            view.needsDisplay = true
        } else {
            view.tick()
        }
    }
}

final class RecordingClockView: NSView {
    /// Room for "Paused 100:00".
    static let width: CGFloat = 124

    var session: RecordingSession
    /// The clock, replaceable for checks.
    var now: () -> Double = { CACurrentMediaTime() }
    private var timer: Timer?
    /// What was drawn last, so a tick that changes nothing draws nothing.
    private(set) var drawnText = ""
    private(set) var drawCount = 0

    init(session: RecordingSession) {
        self.session = session
        super.init(frame: CGRect(x: 0, y: 0, width: RecordingClockView.width, height: 18))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: RecordingClockView.width, height: 18)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        if window == nil {
            return
        }
        // The dot blinks 0.8 s on, 0.4 s off; ticks at 0.2 s catch both edges and every new second.
        let newTimer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        newTimer.tolerance = 0.05
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    /// One reading of the state, so the text and the drawing always agree.
    struct Reading: Equatable {
        var paused: Bool
        var time: String
        var dotOn: Bool

        var text: String {
            var label = "REC"
            if paused {
                label = "Paused"
            }
            var dot = "on"
            if !dotOn {
                dot = "off"
            }
            return "\(label) \(time) \(dot)"
        }
    }

    var reading: Reading {
        let paused = session.isPaused
        let elapsed = session.elapsed(now: now())
        let time = TimeFormat.clock(elapsed)
        // The blink follows the recording's own time: on for 0.8 s, off for 0.4 s.
        var dotOn = true
        if !paused {
            dotOn = elapsed.truncatingRemainder(dividingBy: 1.2) < 0.8
        }
        return Reading(paused: paused, time: time, dotOn: dotOn)
    }

    var currentText: String {
        return reading.text
    }

    /// The time, the state or the blinking dot changed since the last drawing.
    var needsRedraw: Bool {
        return currentText != drawnText
    }

    func tick() {
        if needsRedraw {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let state = reading
        drawnText = state.text
        drawCount += 1
        var dotColor = NSColor(Theme.accent)
        if state.paused {
            dotColor = NSColor(Theme.warning)
        } else if !state.dotOn {
            dotColor = NSColor(Theme.accent).withAlphaComponent(0.3)
        }
        dotColor.setFill()
        let dotY = (bounds.height - 9) / 2
        NSBezierPath(ovalIn: CGRect(x: 0, y: dotY, width: 9, height: 9)).fill()

        var label = L("recording.clock.rec")
        if state.paused {
            label = L("recording.clock.paused")
        }
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor(Theme.text),
        ]
        let labelSize = (label as NSString).size(withAttributes: labelAttributes)
        let textY = (bounds.height - labelSize.height) / 2
        (label as NSString).draw(at: CGPoint(x: 15, y: textY), withAttributes: labelAttributes)
        let timeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(Theme.text),
        ]
        (state.time as NSString).draw(at: CGPoint(x: 15 + labelSize.width + 6, y: textY), withAttributes: timeAttributes)
    }

    // VoiceOver reads the clock like a label: "Recording, 1:23".
    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .staticText
    }

    override func accessibilityLabel() -> String? {
        let state = reading
        if state.paused {
            return L("recording.clock.accessibility.paused", state.time)
        }
        return L("recording.clock.accessibility.recording", state.time)
    }
}

struct HUDButton: View {
    let systemImage: String
    let help: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Theme.accentSoft : Theme.text)
                .frame(width: 30, height: 28)
                .background(isSelected ? Theme.controlSelected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tip(help)
        .accessibilityLabel(help)
    }
}

/// Hosts the HUD in a small floating panel at the top of the screen.
@MainActor
final class RecordingHUDController {
    private var panel: NSPanel?
    /// Called after the bar was dragged somewhere else.
    var onMove: (() -> Void)?
    private var moveObserver: NSObjectProtocol?

    /// The bar's frame on screen, nil while hidden. Its own redraws are not worth frames of the video.
    var frame: CGRect? {
        guard let panel = panel, panel.isVisible, let screen = panel.screen else { return nil }
        return FramePacing.recordingBarZone(barFrame: panel.frame, screenFrame: screen.frame)
    }

    func show(app: AppState) {
        if panel == nil {
            let hosting = NSHostingView(rootView: RecordingHUDView().environment(app))
            let newPanel = KeyablePanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.level = .popUpMenu
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            newPanel.isMovableByWindowBackground = true
            newPanel.becomesKeyOnlyIfNeeded = true
            newPanel.contentView = hosting
            newPanel.isReleasedWhenClosed = false
            newPanel.identifier = NSUserInterfaceItemIdentifier("recording-bar")
            panel = newPanel
            moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: newPanel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onMove?()
                }
            }
        }
        guard let panel = panel, let screen = NSScreen.main else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 400, height: 44)
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 12)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    /// Keeps the panel sized to its content as tools appear and disappear.
    func resize() {
        guard let panel = panel, panel.isVisible else { return }
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        var frame = panel.frame
        let centerX = frame.midX
        frame.size = size
        frame.origin.x = centerX - size.width / 2
        panel.setFrame(frame, display: true, animate: false)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
