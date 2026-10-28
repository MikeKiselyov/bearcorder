import Foundation

/// The files in `Sources/Bugbear/Resources` (What's New pictures, and later the translations).
/// SwiftPM puts them in `Bugbear_Bugbear.bundle`; the build script copies that into the app's
/// `Contents/Resources`. SwiftPM's own `Bundle.module` is not used: it looks for the bundle in the
/// root of the .app (where it would break the code signature) and stops the app when it is missing.
enum AppResources {
    static let bundleName = "Bugbear_Bugbear.bundle"

    /// Inside the app, or next to the executable for builds run from .build (self-test, snapshots).
    static let bundle: Bundle? = {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(bundleName))
        }
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent(bundleName))
        }
        for url in candidates {
            if let found = Bundle(url: url) {
                return found
            }
        }
        return nil
    }()

    /// A file from a folder of the resources, e.g. `url(named: "steps", extensions: ["gif"], in: "WhatsNew")`.
    static func url(named name: String, extensions: [String], in folder: String) -> URL? {
        guard let resources = bundle else { return nil }
        for ext in extensions {
            if let url = resources.url(forResource: name, withExtension: ext, subdirectory: folder) {
                return url
            }
        }
        return nil
    }
}
