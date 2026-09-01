import Foundation

/// The installed plugins — folders under `plugins/`, usually a `git clone` each.
struct PluginsProvider: Provider {
    private let entries: [Entry]

    init(_ config: Config) {
        entries = config.plugins.flatMap { plugin in
            plugin.commands.map { CommandEntry($0, at: plugin.directory) }
        }
    }

    func search(_ query: String) -> [Entry] { entries }
}

/// A command can carry `commands` or `menu`, so picking one is not always doing something: it can
/// put the card into a submenu, which is why running it needs the launcher.
final class CommandEntry: Entry {
    let command: Config.Command
    /// The plugin folder its scripts run from, so `./script.sh` means the plugin's own script.
    let directory: URL
    /// Path of the submenu this row sits in, part of its frecency key.
    private let menu: String

    init(_ command: Config.Command, at directory: URL, in menu: String = "") {
        self.command = command
        self.directory = directory
        self.menu = menu
        super.init(command.name)
    }

    override var subtitle: String? { command.subtitle }
    override var icon: Icon { .symbol(command.icon ?? "terminal") }
    override var frecencyID: String? { "cmd:\(menu)/\(command.name)" }

    override func run(in launcher: Launcher) -> Bool { launcher.open(command, at: directory) }
}
