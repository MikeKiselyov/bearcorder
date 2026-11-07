import Foundation

/// How far an update is, read from the `==>` lines scripts/update.sh writes to its log.
/// The compiler gives no useful count, so the build part follows the time the last build took.
public struct UpdateProgress: Equatable, Sendable {
    public enum Step: String, Sendable {
        case downloading, building, finishing, installing
    }

    public var step: Step
    public var percent: Int

    public init(step: Step, percent: Int) {
        self.step = step
        self.percent = percent
    }

    /// Before any update has run on this Mac.
    public static let defaultBuildSeconds: Double = 150

    private static let buildStart = 5
    private static let buildEnd = 90
    /// The build part stops at this share of its time, so a slow build never looks finished.
    private static let buildCap = 0.95

    /// Log lines in the order they come, with the step and percent they start.
    private static let markers: [(line: String, step: Step, percent: Int)] = [
        ("==> git fetch", .downloading, 0),
        ("==> switching to main", .downloading, 3),
        ("==> updating main", .downloading, 4),
        ("==> build", .building, buildStart),
        ("Build of product", .finishing, buildEnd),
        ("==> version", .finishing, 90),
        ("==> assembling", .finishing, 92),
        ("==> rendering icon", .finishing, 93),
        ("==> signing", .finishing, 94),
        ("==> done", .finishing, 96),
        ("==> replacing", .installing, 97),
        ("==> updated", .installing, 100),
    ]

    /// `elapsedInBuild`: seconds since the build step started; `expectedBuild`: how long the last one took.
    public static func estimate(log: String, elapsedInBuild: Double, expectedBuild: Double?) -> UpdateProgress {
        var progress = UpdateProgress(step: .downloading, percent: 0)
        for line in log.split(separator: "\n") {
            for marker in markers where line == marker.line || line.hasPrefix(marker.line + " ") || line.hasPrefix(marker.line + ":") {
                progress = UpdateProgress(step: marker.step, percent: marker.percent)
            }
        }
        if progress.step == .building {
            let expected = expectedBuild ?? defaultBuildSeconds
            let share = min(max(elapsedInBuild / expected, 0), buildCap)
            progress.percent = buildStart + Int(Double(buildEnd - buildStart) * share)
        }
        return progress
    }

    /// A build shorter than this rebuilt almost nothing (a retry) and says nothing about the next one.
    public static let shortestFullBuildSeconds: Double = 20

    /// The seconds in "Build of product 'App' complete! (91.39s)", the time to expect next time.
    /// Nil for a build that rebuilt almost nothing.
    public static func buildSeconds(inLog log: String) -> Double? {
        for line in log.split(separator: "\n") where line.hasPrefix("Build of product") {
            guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: "s") else { continue }
            if let seconds = Double(line[line.index(after: open)..<close]), seconds >= shortestFullBuildSeconds {
                return seconds
            }
        }
        return nil
    }
}
