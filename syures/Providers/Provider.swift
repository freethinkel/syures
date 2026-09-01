import Foundation

/// A source of the rows the card shows under the query.
///
/// One method, and the scoring lives inside the provider rather than outside it, for the sake of
/// sources whose answer is in no list at all: a calculator reads `2+2`, and "4" would never match
/// the query it came from.
protocol Provider {
    func search(_ query: String) -> [Match]
}

struct Match {
    let item: Launcher.Item
    let score: Int
    /// An answer to the query rather than a match for it. One of these in the list and only
    /// these are shown.
    var exclusive = false
}

/// A candidate with its match key precomputed, so the keystroke path allocates nothing.
struct Entry {
    let item: Launcher.Item
    let name: String
    /// Key of this item's frecency record.
    let frecencyID: String
    /// `name` lowercased, as UTF-8 bytes.
    private let haystack: [UInt8]
    /// Positional bonus per byte of `haystack`.
    private let bonus: [Int]

    init(_ item: Launcher.Item, in menu: String = "") {
        self.item = item
        name = item.name
        frecencyID = Launcher.frecencyID(item, in: menu)
        (haystack, bonus) = Launcher.matchKey(name)
    }

    /// One matcher for every provider — otherwise their scores could not be compared.
    func score(_ needle: [UInt8]) -> Int? {
        Launcher.fuzzyScore(needle, haystack, bonus: bonus)
    }

    /// The rows of a fixed list that fit the query, the shape every list-backed provider needs.
    static func search(_ entries: [Entry], _ query: String) -> [Match] {
        let needle = Array(query.lowercased().utf8)
        return entries.compactMap { entry in
            entry.score(needle).map { Match(item: entry.item, score: $0) }
        }
    }
}

extension Launcher {
    /// Every provider, in priority order: on an equal score the one listed first wins. Commands
    /// are written by hand, so they sit above installed apps. Adding a provider is adding a file
    /// next to this one and a word to this array — a Swift type cannot be registered at runtime,
    /// which is what `menu` scripts are for.
    /// Rebuilt on every activation, so a provider reads the config in its `init` and needs no
    /// reload of its own. Free because the one source that touches the disk scans once.
    static func allProviders(_ config: Config) -> [any Provider] {
        [Calculator(), CommandsProvider(config), AppsProvider()]
    }
}
