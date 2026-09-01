import Foundation

/// A source of the rows the card shows under the query.
///
/// One method, and it takes the query, because a source's answer need not be in any list: a
/// calculator reads `2+2` and builds the row for it. A list-backed source ignores the query here
/// and lets `Entry.score` do the matching.
protocol Provider {
    func search(_ query: String) -> [Entry]
}

extension Launcher {
    /// Every provider, in priority order: on an equal score the one listed first wins. Commands
    /// are written by hand, so they sit above installed apps. Adding a provider is adding a file
    /// next to this one and a word to this array — a Swift type cannot be registered at runtime,
    /// which is what `menu` scripts are for.
    ///
    /// Rebuilt on every activation, so a provider reads the config in its `init` and needs no
    /// reload of its own. Free because the one source that touches the disk scans once.
    static func allProviders(_ config: Config) -> [any Provider] {
        [Calculator(), CommandsProvider(config), AppsProvider()]
    }
}
