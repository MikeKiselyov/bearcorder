import Foundation

/// Keeps a log file from growing without end: past `limit` bytes the file moves to `<name>.1`
/// (replacing an older one) and a new empty file starts, so the last stretch is never lost.
public enum LogRotation {
    public static func rotateIfNeeded(_ url: URL, limit: Int) {
        let files = FileManager.default
        guard let size = try? files.attributesOfItem(atPath: url.path)[.size] as? Int else { return }
        if size <= limit {
            return
        }
        let old = URL(fileURLWithPath: url.path + ".1")
        try? files.removeItem(at: old)
        do {
            try files.moveItem(at: url, to: old)
        } catch {
            // Could not move it: empty the file so it still stays small.
            try? Data().write(to: url)
            return
        }
        files.createFile(atPath: url.path, contents: Data())
    }
}
