import AppKit

/// The installed apps — the launcher's default source.
struct AppsProvider: Provider {
    /// ponytail: a fixed list of paths, nothing watching the file system. An app installed while
    /// the launcher runs shows up after a restart — add a watcher if that starts to matter.
    static let searchPaths = [
        "/Applications", "/Applications/Utilities",
        "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    /// Scanned once for the life of the process, which is what "scanned at launch" already meant
    /// — and what makes rebuilding the provider list on every activation free.
    nonisolated(unsafe) private static let entries = installed().map(AppEntry.init)

    func search(_ query: String) -> [Entry] { AppsProvider.entries }

    static func installed() -> [URL] {
        searchPaths
            .flatMap { path -> [URL] in
                (try? FileManager.default.contentsOfDirectory(
                    at: URL(filePath: path), includingPropertiesForKeys: nil)) ?? []
            }
            .filter { $0.pathExtension == "app" }
    }
}

final class AppEntry: Entry {
    let url: URL

    init(_ url: URL) {
        self.url = url
        super.init(url.deletingPathExtension().lastPathComponent)
    }

    override var icon: Icon? { .file(url) }
    /// The key launch counts have always been kept under, so history survives.
    override var frecencyID: String { "app:\(url.path)" }

    override func run(in launcher: Launcher) -> Bool {
        NSWorkspace.shared.open(url)
        return false
    }
}
