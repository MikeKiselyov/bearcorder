import Foundation

/// Keeps the end of a stream that comes in chunks, so a long output never sits in memory whole.
public struct StreamTail: Sendable {
    private let limit: Int
    private var data = Data()
    private var total = 0

    public init(limit: Int) {
        self.limit = limit
    }

    /// True when the stream was longer than the limit and its start is gone.
    public var isCut: Bool {
        return total > limit
    }

    var heldBytes: Int {
        return data.count
    }

    public mutating func append(_ chunk: Data) {
        total += chunk.count
        data.append(chunk)
        // Trimming only at twice the limit keeps the copying rare.
        if data.count > limit * 2 {
            data = Data(data.suffix(limit + 1))
        }
    }

    /// All of a stream that fits; otherwise whole lines from its end, `limit` bytes at most.
    public func tail() -> Data {
        if !isCut { return data }
        // One byte more than the limit tells a cut at a line start from a cut inside a line.
        let end = Data(data.suffix(limit + 1))
        if let newline = end.firstIndex(of: 10), newline + 1 < end.count {
            return Data(end[(newline + 1)...])
        }
        // One line longer than the limit: its end.
        return Data(end.suffix(limit))
    }
}
