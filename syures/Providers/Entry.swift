import AppKit

/// A row in the list: it knows how well it fits the query and what to do when it is picked.
///
/// Providers subclass it, which is where an app's icon, a command's submenu and an answer's
/// pasteboard live — `Launcher` never switches over what a row happens to be.
class Entry: Hashable {
    let name: String
    /// `name` lowercased as UTF-8, with a positional bonus per byte: the match key, built once.
    private let haystack: [UInt8]
    private let bonus: [Int]

    init(_ name: String) {
        self.name = name
        (haystack, bonus) = Launcher.matchKey(name)
    }

    var subtitle: String? { nil }
    var icon: Icon? { nil }
    /// Key of this row's frecency record. Empty means nothing worth remembering — an answer is
    /// recomputed from the query every time, so its launch count would mean nothing.
    var frecencyID: String { "" }
    /// An answer to the query rather than a match for it. One of these in the list and only
    /// these are shown.
    var exclusive: Bool { false }

    /// How well the row fits the query, or `nil` when it does not fit at all. One matcher for
    /// every provider — otherwise their scores could not be compared — which an answer overrides,
    /// since "4" would never match the `2+2` it came from.
    func score(_ needle: [UInt8]) -> Int? { Launcher.fuzzyScore(needle, haystack, bonus: bonus) }

    /// Carries the row out. `true` means a submenu opened, so the panel stays up.
    func run(in launcher: Launcher) -> Bool { false }

    enum Icon {
        /// An SF Symbol, an emoji, or a Nerd Font glyph.
        case symbol(String)
        /// The file's own icon, the way an app is drawn.
        case file(URL)
    }

    // Identity, so a row is its own id in the list and two apps of the same name stay apart.
    static func == (lhs: Entry, rhs: Entry) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
