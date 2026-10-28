import AppKit

/// The editors' last choices, so a new screenshot or clip opens the way the last one was left:
/// the same tool, color, size, badge, format. Only what the person changes is remembered; opening
/// an older capture with other settings does not change it.
@MainActor
enum EditorMemory {
    /// Self-tests point this at scratch defaults so they leave the person's choices alone.
    static var override: UserDefaults?
    private static let testStore = UserDefaults(suiteName: "\(Bundle.main.bundleIdentifier ?? "bugbear").tests")

    /// Where the choices are kept. While the e2e tests drive the app (automation on) they go to a
    /// separate store, so the tests' clicks never become the person's choices. Checked on every
    /// use: a copy that stays open after the tests switch automation off saves the person's again.
    static var defaults: UserDefaults {
        if let scratch = override {
            return scratch
        }
        if Automation.isEnabled, let tests = testStore {
            return tests
        }
        return UserDefaults.standard
    }

    // MARK: Screenshot editor

    /// The drawing tool; Select and Crop are steps of the work, not a choice to start with.
    static var screenshotTool: AnnotationTool {
        get { return AnnotationTool(rawValue: defaults.string(forKey: "screenshotTool") ?? "") ?? .arrow }
        set {
            if newValue == .select || newValue == .crop { return }
            defaults.set(newValue.rawValue, forKey: "screenshotTool")
        }
    }

    static var screenshotColor: AnnotationColor {
        get {
            guard let hex = defaults.object(forKey: "screenshotColor") as? Int else { return .coral }
            return AnnotationColor(hex: UInt32(hex))
        }
        set { defaults.set(Int(newValue.hex), forKey: "screenshotColor") }
    }

    static var screenshotStroke: StrokeSize {
        get { return StrokeSize(rawValue: defaults.string(forKey: "screenshotStroke") ?? "") ?? .thick }
        set { defaults.set(newValue.rawValue, forKey: "screenshotStroke") }
    }

    static var screenshotTextPoints: CGFloat {
        get {
            guard let points = defaults.object(forKey: "screenshotTextPoints") as? Double else { return TextSizes.standard }
            return CGFloat(points)
        }
        set { defaults.set(Double(newValue), forKey: "screenshotTextPoints") }
    }

    static var screenshotShowsBadge: Bool {
        get { return defaults.bool(forKey: "screenshotShowsBadge") }
        set { defaults.set(newValue, forKey: "screenshotShowsBadge") }
    }

    static var screenshotBadgeCorner: BadgeCorner {
        get { return BadgeCorner(rawValue: defaults.string(forKey: "screenshotBadgeCorner") ?? "") ?? .topRight }
        set { defaults.set(newValue.rawValue, forKey: "screenshotBadgeCorner") }
    }

    /// New text has no label behind it, in both editors.
    static var clearTextBackground: Bool {
        get { return defaults.bool(forKey: "clearTextBackground") }
        set { defaults.set(newValue, forKey: "clearTextBackground") }
    }

    static var shapeFill: Bool {
        get { return defaults.bool(forKey: "shapeFill") }
        set { defaults.set(newValue, forKey: "shapeFill") }
    }

    static var screenshotFormat: String {
        get { return defaults.string(forKey: "screenshotExportFormat") ?? "" }
        set { defaults.set(newValue, forKey: "screenshotExportFormat") }
    }

    // MARK: Video editor

    /// What the video editor remembers: the switches and export choices, not the edits.
    private static let videoKey = "videoEditorChoices"

    /// A project for a clip opened for the first time, with the last choices.
    static func newVideoProject(duration: Double) -> VideoProject {
        var project = VideoProject(duration: duration)
        guard let saved = defaults.data(forKey: videoKey), let choices = try? JSONDecoder().decode(VideoChoices.self, from: saved) else { return project }
        project.showClicks = choices.showClicks
        project.showKeys = choices.showKeys
        project.showSteps = choices.showSteps
        project.showBadge = choices.showBadge
        project.badgeCorner = choices.badgeCorner
        project.format = choices.format
        project.quality = choices.quality
        project.gifFramesPerSecond = choices.gifFramesPerSecond
        project.sizeLimitMB = choices.sizeLimitMB
        return project
    }

    /// Remembers the choices that changed between two states of a project.
    static func rememberVideoChanges(from old: VideoProject, to new: VideoProject) {
        var choices = VideoChoices(from: newVideoProject(duration: 1))
        var changed = false
        if old.showClicks != new.showClicks {
            choices.showClicks = new.showClicks
            changed = true
        }
        if old.showKeys != new.showKeys {
            choices.showKeys = new.showKeys
            changed = true
        }
        if old.isShowingSteps != new.isShowingSteps {
            choices.showSteps = new.isShowingSteps
            changed = true
        }
        if old.showBadge != new.showBadge {
            choices.showBadge = new.showBadge
            changed = true
        }
        if old.badgeCorner != new.badgeCorner {
            choices.badgeCorner = new.badgeCorner
            changed = true
        }
        if old.format != new.format {
            choices.format = new.format
            changed = true
        }
        if old.quality != new.quality {
            choices.quality = new.quality
            changed = true
        }
        if old.gifFramesPerSecond != new.gifFramesPerSecond {
            choices.gifFramesPerSecond = new.gifFramesPerSecond
            changed = true
        }
        if old.sizeLimitMB != new.sizeLimitMB {
            choices.sizeLimitMB = new.sizeLimitMB
            changed = true
        }
        if !changed { return }
        if let data = try? JSONEncoder().encode(choices) {
            defaults.set(data, forKey: videoKey)
        }
    }

    private struct VideoChoices: Codable {
        var showClicks: Bool
        var showKeys: Bool
        var showSteps: Bool?
        var showBadge: Bool
        var badgeCorner: BadgeCorner
        var format: VideoExportFormat
        var quality: VideoQuality
        var gifFramesPerSecond: Int
        var sizeLimitMB: Int?

        init(from project: VideoProject) {
            showClicks = project.showClicks
            showKeys = project.showKeys
            showSteps = project.showSteps
            showBadge = project.showBadge
            badgeCorner = project.badgeCorner
            format = project.format
            quality = project.quality
            gifFramesPerSecond = project.gifFramesPerSecond
            sizeLimitMB = project.sizeLimitMB
        }
    }
}
