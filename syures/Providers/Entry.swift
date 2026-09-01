import AppKit

/// A row in the list: it knows how well it fits the query and what to do when it is picked.
///
/// Providers subclass it, which is where an app's icon, a command's submenu and an answer's
/// pasteboard live — `Launcher` never switches over what a row happens to be.
class Entry: Hashable {
    let name: String
    /// `name` lowercased as UTF-8, with a positional bonus per byte. Built on the first `score`
    /// and not before: a row the query never has to match — an answer, or the one row a `prefix`
    /// puts on screen — is built on every keystroke and would pay for a key it never reads.
    private lazy var key = Launcher.matchKey(name)

    init(_ name: String) {
        self.name = name
    }

    var subtitle: String? { nil }
    /// Overridden by every provider; the default is for the next one, before it picks a glyph.
    var icon: Icon { .symbol("sparkles") }
    /// Key of this row's frecency record. `nil` for a row recomputed from the query every time —
    /// an answer's launch count would mean nothing.
    var frecencyID: String? { nil }
    /// An answer to the query rather than a match for it. One of these in the list and only
    /// these are shown.
    var exclusive: Bool { false }

    /// How well the row fits the query, or `nil` when it does not fit at all. One matcher for
    /// every provider — otherwise their scores could not be compared — which an answer overrides,
    /// since "4" would never match the `2+2` it came from.
    func score(_ needle: [UInt8]) -> Int? { Launcher.fuzzyScore(needle, key.haystack, bonus: key.bonus) }

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
