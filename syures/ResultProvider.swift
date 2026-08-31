import AppKit

/// Where a result in the list comes from. Three shapes, because there are three costs:
///
/// - `entries()` — a list that does not depend on the query (apps). Asked once, ranked with
///   everything else, so it competes on fuzzy score and then on frecency.
/// - `immediate(_:)` — computed from the query in the same frame (calculator). Pinned above the
///   ranked list, the way Raycast puts a calculation on top.
/// - `deferred(_:)` — a subprocess or the network (a `menu` plugin). Debounced, and dropped if
///   the query moved on.
///
/// A provider implements the one it needs; the rest default to empty.
protocol ResultProvider {
    /// Typed at the root, this hands the rest of the query to the provider instead of searching.
    var prefix: String? { get }
    func entries() -> [Launcher.Provided]
    func immediate(_ query: String) -> [Launcher.Provided]
    func deferred(_ query: String) async -> [Launcher.Provided]
    /// Only paid by a provider that has a `deferred`.
    var debounce: Duration { get }
}

extension ResultProvider {
    var prefix: String? { nil }
    var debounce: Duration { .milliseconds(300) }
    func entries() -> [Launcher.Provided] { [] }
    func immediate(_ query: String) -> [Launcher.Provided] { [] }
    func deferred(_ query: String) async -> [Launcher.Provided] { [] }
}

/// `2.5*2` -> `= 5`. Synchronous and pure, which is why it can run on every keystroke.
struct Calculator: ResultProvider {
    func immediate(_ query: String) -> [Launcher.Provided] { Launcher.calculator(query) }
}

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
