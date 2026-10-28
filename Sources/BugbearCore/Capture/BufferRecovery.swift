/// The screen buffer stopped on its own: the displays went away (the lid closed, a monitor was
/// unplugged, the Mac went to sleep). It comes back by itself: soon after the stop, then less
/// often, and at once when a display appears or the Mac wakes up. Turning the buffer off or a
/// successful start ends the wait.
public struct BufferRecovery: Equatable {
    /// Seconds before each try; the last one repeats until the buffer is back.
    public static let delays: [Double] = [2, 5, 15, 30, 60]

    public private(set) var isWaiting = false
    public private(set) var attempts = 0

    public init() {}

    /// The buffer stopped, or could not start because no display was there. Waiting already, the
    /// tries keep their pace.
    public mutating func bufferLost() {
        if isWaiting { return }
        isWaiting = true
        attempts = 0
    }

    /// Seconds until the next try, nil when nothing is waiting.
    public mutating func nextDelay() -> Double? {
        if !isWaiting { return nil }
        var index = attempts
        if index >= BufferRecovery.delays.count {
            index = BufferRecovery.delays.count - 1
        }
        attempts += 1
        return BufferRecovery.delays[index]
    }

    /// Tries that fail for another reason than a missing display (a setting the capture refuses)
    /// would fail forever; the buffer stays off after this many.
    public static let triesForOtherErrors = 3

    /// After a try failed: no display yet means waiting on; any other error gives up after a few tries.
    public func keepsTrying(afterNoDisplay noDisplay: Bool) -> Bool {
        if noDisplay {
            return true
        }
        return attempts < BufferRecovery.triesForOtherErrors
    }

    /// The buffer runs again, or the person turned it off.
    public mutating func ended() {
        isWaiting = false
        attempts = 0
    }
}
