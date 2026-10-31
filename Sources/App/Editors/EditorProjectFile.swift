import AppCore
import Foundation

/// The project file writer of an open editor. A failed save goes to the log every time and shows
/// a toast once, then again only after a save worked in between.
enum EditorProjectFile {
    static func writer(for url: URL) -> ProjectFileWriter {
        let notice = SaveFailureNotice()
        return ProjectFileWriter(
            url: url,
            onFailure: { error in notice.failed(error, url: url) },
            onSuccess: { notice.succeeded() }
        )
    }
}

/// Remembers whether the person was already told that saving failed. Called on the writer's queue.
private final class SaveFailureNotice: @unchecked Sendable {
    private let lock = NSLock()
    private var shown = false

    func failed(_ error: Error, url: URL) {
        let reason = error.localizedDescription
        Log.error("editor: could not save \(url.path): \(reason)")
        lock.lock()
        let alreadyShown = shown
        shown = true
        lock.unlock()
        if alreadyShown { return }
        Task { @MainActor in
            Toast.shared.show(L("editors.saveFailed", reason), symbol: "exclamationmark.triangle")
        }
    }

    func succeeded() {
        lock.lock()
        shown = false
        lock.unlock()
    }
}
