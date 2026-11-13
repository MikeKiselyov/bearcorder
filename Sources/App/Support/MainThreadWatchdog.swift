import Foundation
import AppCore

/// Logs when the main thread stops answering: a timer on its own queue pings the main queue once
/// a second and the answer says how long it waited. An app that never answers again leaves the
/// "not answering" line, written from the timer's queue.
enum MainThreadWatchdog {
    private static let queue = DispatchQueue(label: "app.watchdog", qos: .utility)
    /// Both are used only on `queue`.
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?
    nonisolated(unsafe) private static var waiting = false
    nonisolated(unsafe) private static var pingedAt: UInt64 = 0
    nonisolated(unsafe) private static var saidNotAnswering = false

    /// `report` gets the log line of a stall, on the main thread; `notAnswering` gets one line per
    /// stall while it still lasts, on the timer's queue.
    static func start(interval: Double = 1, threshold: UInt64 = MainThreadStall.defaultThreshold, report: @escaping @Sendable (String) -> Void = { Log.info($0) }, notAnswering: @escaping @Sendable (String) -> Void = { Log.info($0) }) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(interval * 100)))
        timer.setEventHandler {
            // No new ping while one waits: a stall is one answer, so one line, however long it lasts.
            if waiting {
                let waited = DispatchTime.now().uptimeNanoseconds - self.pingedAt
                if !saidNotAnswering && waited > threshold {
                    saidNotAnswering = true
                    notAnswering("main thread not answering for \(waited / 1_000_000) ms")
                }
                return
            }
            waiting = true
            saidNotAnswering = false
            // Uptime stands still while the Mac sleeps, so sleep and wake is not a stall.
            let pingedAt = DispatchTime.now().uptimeNanoseconds
            self.pingedAt = pingedAt
            DispatchQueue.main.async {
                let answeredAt = DispatchTime.now().uptimeNanoseconds
                queue.async { waiting = false }
                if let line = MainThreadStall.logLine(pingedAt: pingedAt, answeredAt: answeredAt, threshold: threshold) {
                    report(line)
                }
            }
        }
        queue.async {
            self.timer?.cancel()
            self.timer = timer
            waiting = false
            timer.resume()
        }
    }

    static func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }
}
