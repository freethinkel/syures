import AppKit

/// The installed apps — the launcher's default source, scanned once.
struct AppsProvider: ResultProvider {
    /// ponytail: a fixed list of paths, no `NSMetadataQuery` — apps that appear while the panel
    /// is open wait for a restart, which is what a scan-at-launch already meant.
    static let searchPaths = [
        "/Applications", "/Applications/Utilities",
        "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    private let apps: [Launcher.Provided] = searchPaths
        .flatMap { path -> [URL] in
            (try? FileManager.default.contentsOfDirectory(
                at: URL(filePath: path), includingPropertiesForKeys: nil)) ?? []
        }
        .filter { $0.pathExtension == "app" }
        .map {
            Launcher.Provided(name: $0.deletingPathExtension().lastPathComponent, icon: .file($0),
                              action: .open($0), id: "app:\($0.path)")  // the pre-provider key
        }

    func entries() -> [Launcher.Provided] { apps }
}
