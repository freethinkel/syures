import AppKit

/// The installed apps — the launcher's default source, scanned once.
struct AppsProvider: Provider {
    /// ponytail: a fixed list of paths, nothing watching the file system. An app installed while
    /// the launcher runs shows up after a restart — add a watcher if that starts to matter.
    static let searchPaths = [
        "/Applications", "/Applications/Utilities",
        "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    private let entries = AppsProvider.installed().map { Entry(.provided($0)) }

    func search(_ query: String) -> [Match] { Entry.search(entries, query) }

    static func installed() -> [Launcher.Provided] {
        searchPaths
            .flatMap { path -> [URL] in
                (try? FileManager.default.contentsOfDirectory(
                    at: URL(filePath: path), includingPropertiesForKeys: nil)) ?? []
            }
            .filter { $0.pathExtension == "app" }
            .map {
                Launcher.Provided(name: $0.deletingPathExtension().lastPathComponent,
                                  icon: .file($0), action: .open($0),
                                  id: "app:\($0.path)")  // the pre-provider frecency key
            }
    }
}
