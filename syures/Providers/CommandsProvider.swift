import Foundation

/// The config's own `commands` — the plugins the user wrote themselves.
struct CommandsProvider: Provider {
    private let entries: [Entry]

    init(_ config: Config) {
        entries = config.commands.map { CommandEntry($0) }
    }

    func search(_ query: String) -> [Entry] { entries }
}

/// A command can carry `commands` or `menu`, so picking one is not always doing something: it can
/// put the card into a submenu, which is why running it needs the launcher.
final class CommandEntry: Entry {
    let command: Config.Command
    /// Path of the submenu this row sits in, part of its frecency key.
    private let menu: String

    init(_ command: Config.Command, in menu: String = "") {
        self.command = command
        self.menu = menu
        super.init(command.name)
    }

    override var subtitle: String? { command.subtitle }
    override var icon: Icon { .symbol(command.icon ?? "terminal") }
    override var frecencyID: String? { "cmd:\(menu)/\(command.name)" }

    override func run(in launcher: Launcher) -> Bool { launcher.open(command) }
}
