import Foundation

/// Decides whether the main queue's answer to the watchdog's ping came late enough to log.
/// Times are uptime nanoseconds, a clock that stands still while the Mac sleeps.
public enum MainThreadStall {
    public static let defaultThreshold: UInt64 = 1_000_000_000

    /// The log line for a stall, nil when the answer came in time. The test scripts fail on this
    /// line (scripts/test/lib/run-log.sh), so its words stay as they are.
    public static func logLine(pingedAt: UInt64, answeredAt: UInt64, threshold: UInt64 = defaultThreshold) -> String? {
        if answeredAt < pingedAt {
            return nil
        }
        let waited = answeredAt - pingedAt
        if waited <= threshold {
            return nil
        }
        return "main thread stalled \(waited / 1_000_000) ms"
    }
}
