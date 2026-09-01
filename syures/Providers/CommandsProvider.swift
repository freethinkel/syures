import Foundation

/// The config's own `commands` — the plugins the user wrote themselves.
///
/// Unlike the other providers this one yields `.command` items, not `.provided` ones: a command
/// can carry `commands` or `menu`, and opening a submenu is a state the card goes into, which a
/// `Provided` has no way to express.
struct CommandsProvider: Provider {
    private let entries: [Entry]

    init(_ config: Config) {
        entries = config.commands.map { Entry(.command($0)) }
    }

    func search(_ query: String) -> [Match] { Entry.search(entries, query) }
}
