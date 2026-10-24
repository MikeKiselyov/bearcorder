import Foundation

/// Finds how far content scrolled between two frames of the same area, so the frames can be glued
/// into one long screenshot. Each pixel row is reduced to a brightness profile; rows match when their
/// profiles are close, because a browser re-renders text slightly differently after a scroll.
public enum ScrollStitcher {
    /// Number of brightness bins per row.
    public static let bins = 64
    /// Average difference per bin (0-255) under which two rows count as the same.
    static let rowTolerance = 6
    /// No single bin may differ more than this: re-rendered text shifts a little everywhere,
    /// different content differs a lot somewhere.
    static let binTolerance = 24

    /// Brightness profile of one RGBA row, or nil for a flat row (one color), which matches anywhere
    /// and says nothing about the scroll.
    public static func rowSignature(_ pixels: UnsafeBufferPointer<UInt8>, rowStart: Int, width: Int) -> [UInt8]? {
        var profile = [UInt8](repeating: 0, count: bins)
        var lowest = 255
        var highest = 0
        for bin in 0..<bins {
            let from = bin * width / bins
            let to = max(from + 1, (bin + 1) * width / bins)
            var sum = 0
            var count = 0
            for x in from..<min(to, width) {
                let offset = rowStart + x * 4
                // Rec. 601 luma, integer.
                let luma = (Int(pixels[offset]) * 299 + Int(pixels[offset + 1]) * 587 + Int(pixels[offset + 2]) * 114) / 1000
                sum += luma
                count += 1
                lowest = min(lowest, luma)
                highest = max(highest, luma)
            }
            if count > 0 {
                profile[bin] = UInt8(sum / count)
            }
        }
        if highest - lowest < 12 { return nil }
        return profile
    }

    static func same(_ first: [UInt8], _ second: [UInt8], binLimit: Int = binTolerance, averageLimit: Int = rowTolerance) -> Bool {
        var total = 0
        for index in 0..<min(first.count, second.count) {
            let difference = abs(Int(first[index]) - Int(second[index]))
            if difference > binLimit {
                return false
            }
            total += difference
        }
        return total <= averageLimit * first.count
    }

    /// Largest average difference per bin (0-255) at which a shift is accepted.
    static let acceptedError = 22.0
    /// The winner must beat every clearly different shift by this factor. Measured on Safari:
    /// real scrolls score about 0.5-0.6 of the runner-up, frames without a true match about 0.9.
    static let requiredLead = 0.75
    /// Cost per bin when a row with content meets an empty row.
    static let flatMismatchPenalty = 60

    /// True when a row did not change at all between two frames (sticky headers, footers, toolbars).
    public static func isStationary(_ first: [UInt8]?, _ second: [UInt8]?) -> Bool {
        guard let upper = first, let lower = second else { return false }
        return same(upper, lower, binLimit: 3, averageLimit: 1)
    }

    /// Rows the content moved up from `previous` to `next` (both the same height), or nil when no
    /// shift explains the frames (nothing scrolled, or the page changed). Rows that stay put
    /// (a sticky header) don't count for or against a shift.
    public static func offset(previous: [[UInt8]?], next: [[UInt8]?], minimumShift: Int = 1) -> Int? {
        let best = bestShift(previous: previous, next: next, minimumShift: minimumShift)
        if best.error > acceptedError { return nil }
        if best.error > requiredLead * best.runnerUp { return nil }
        return best.shift
    }

    /// The shift with the smallest average difference between overlapping rows ("block matching").
    /// `score` is 1 for a perfect match and falls as the error grows (for diagnostics).
    public static func bestShift(previous: [[UInt8]?], next: [[UInt8]?], minimumShift: Int = 1) -> (shift: Int?, score: Double, compared: Int, error: Double, runnerUp: Double) {
        let height = min(previous.count, next.count)
        if height < 8 { return (shift: nil, score: 0, compared: 0, error: 255, runnerUp: 255) }
        // Rows nearly identical at the same place in both frames did not scroll: sticky headers and toolbars.
        var stationary = [Bool](repeating: false, count: height)
        for row in 0..<height {
            if isStationary(previous[row], next[row]) {
                stationary[row] = true
            }
        }
        var bestShift: Int? = nil
        var bestError = Double.greatestFiniteMagnitude
        var bestCompared = 0
        var errors = [Double](repeating: Double.greatestFiniteMagnitude, count: height)
        for shift in minimumShift..<height {
            var compared = 0
            var total = 0
            for row in 0..<(height - shift) {
                if stationary[row] || stationary[row + shift] { continue }
                let upper = previous[row + shift]
                let lower = next[row]
                if upper == nil && lower == nil { continue }
                compared += 1
                if let first = upper, let second = lower {
                    total += difference(first, second)
                } else {
                    // Text against an empty row: clearly the wrong shift.
                    total += flatMismatchPenalty * bins
                }
            }
            // Too little overlap to be sure.
            if compared < 12 { continue }
            let error = Double(total) / Double(compared * bins)
            errors[shift] = error
            if error < bestError - 0.0001 {
                bestError = error
                bestShift = shift
                bestCompared = compared
            }
        }
        guard let found = bestShift else {
            return (shift: nil, score: 0, compared: 0, error: 255, runnerUp: 255)
        }
        // The best error among shifts clearly different from the winner: a real match stands out.
        var runnerUp = Double.greatestFiniteMagnitude
        for shift in minimumShift..<height where abs(shift - found) > 24 {
            runnerUp = min(runnerUp, errors[shift])
        }
        return (shift: found, score: 1 - bestError / 255, compared: bestCompared, error: bestError, runnerUp: runnerUp)
    }

    /// Sum of absolute bin differences.
    static func difference(_ first: [UInt8], _ second: [UInt8]) -> Int {
        var total = 0
        for index in 0..<min(first.count, second.count) {
            total += abs(Int(first[index]) - Int(second[index]))
        }
        return total
    }

    /// For one shift: rows compared, matched, skipped as stationary, and the typical bin difference.
    public static func diagnose(previous: [[UInt8]?], next: [[UInt8]?], shift: Int) -> String {
        let height = min(previous.count, next.count)
        var stationary = 0
        var compared = 0
        var matched = 0
        var maxDifferences: [Int] = []
        for row in 0..<(height - shift) {
            if let upper = previous[row], let lower = next[row], same(upper, lower) { stationary += 1 }
            guard let upper = previous[row + shift], let lower = next[row] else { continue }
            compared += 1
            if same(upper, lower) { matched += 1 }
            var largest = 0
            for index in 0..<min(upper.count, lower.count) {
                largest = max(largest, abs(Int(upper[index]) - Int(lower[index])))
            }
            maxDifferences.append(largest)
        }
        maxDifferences.sort()
        var median = -1
        if !maxDifferences.isEmpty { median = maxDifferences[maxDifferences.count / 2] }
        return "compared=\(compared) matched=\(matched) stationaryAtTop=\(stationary) medianMaxBinDiff=\(median)"
    }

    /// True when two frames are the same (the page did not move: the end is reached). Much stricter
    /// than row matching: table rows look alike, and a moved page must never pass for an unmoved one.
    public static func isSame(_ previous: [[UInt8]?], _ next: [[UInt8]?]) -> Bool {
        if previous.count != next.count { return false }
        var compared = 0
        var matched = 0
        for row in 0..<previous.count {
            let upper = previous[row]
            let lower = next[row]
            if upper == nil && lower == nil { continue }
            compared += 1
            guard let first = upper, let second = lower else { continue }
            if same(first, second, binLimit: 3, averageLimit: 1) {
                matched += 1
            }
        }
        if compared == 0 { return true }
        return Double(matched) / Double(compared) > 0.98
    }
}
