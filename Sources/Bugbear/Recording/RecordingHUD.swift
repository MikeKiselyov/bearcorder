import AppKit
import SwiftUI

/// Floating control bar shown while recording: timer, pause, draw tools, stop.
struct RecordingHUDView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var overlay = app.overlay
        HStack(spacing: 8) {
            if let session = app.recording {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(session.isPaused ? Theme.warning : Theme.accent)
                            .frame(width: 9, height: 9)
                            .opacity(session.isPaused ? 1 : blinkOpacity)
                        Text(session.isPaused ? "Paused" : "REC")
                            .font(.system(size: 12, weight: .bold))
                        Text(TimeFormat.clock(session.elapsed()))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .frame(minWidth: 110, alignment: .leading)
                }

                HUDButton(systemImage: session.isPaused ? "play.fill" : "pause.fill", help: session.isPaused ? "Resume the recording (\(HotKeySettings.shared.text(for: .recordPause)))" : "Pause the recording without ending it (\(HotKeySettings.shared.text(for: .recordPause)))") {
                    session.togglePause()
                }
            } else {
                Text("Draw on screen")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.leading, 4)
            }

            divider

            HUDButton(systemImage: "pencil.and.scribble", help: overlay.isDrawing ? "Stop drawing and use the screen normally again (Esc)" : "Draw arrows and boxes on screen to point things out (\(HotKeySettings.shared.text(for: .draw)))", isSelected: overlay.isDrawing) {
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
                    .help("Draw in \(color.rawValue)")
                }
                divider
                HUDButton(systemImage: overlay.autoFade ? "timer" : "pin.fill", help: overlay.autoFade ? "Marks fade after 3 s (click to keep)" : "Marks stay (click to fade)") {
                    overlay.autoFade.toggle()
                }
                HUDButton(systemImage: "arrow.uturn.backward", help: "Undo the last mark (⌘Z)") {
                    overlay.undo()
                }
                HUDButton(systemImage: "trash", help: "Clear all marks from the screen (Delete)") {
                    overlay.clear()
                }
            }

            divider

            if app.recording != nil {
                HUDButton(systemImage: "xmark", help: "Stop and throw the recording away without saving") {
                    app.discardRecording()
                }
                Button {
                    Task { await app.stopRecording() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill").font(.system(size: 10))
                        Text("Stop").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Stop recording and open it in the editor (\(HotKeySettings.shared.text(for: .recordToggle)))")
            } else {
                HUDButton(systemImage: "xmark", help: "Close the drawing bar") {
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

    private var blinkOpacity: Double {
        let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2)
        return phase < 0.8 ? 1 : 0.3
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
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Hosts the HUD in a small floating panel at the top of the screen.
@MainActor
final class RecordingHUDController {
    private var panel: NSPanel?

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
            panel = newPanel
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
