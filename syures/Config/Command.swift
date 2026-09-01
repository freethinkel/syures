import Foundation

extension Config {
    /// A plugin is just an entry in the config: match it by name, then shell out.
    struct Command: Decodable, Hashable {
        var name: String
        var subtitle: String?
        /// SF Symbol name.
        var icon: String?
        /// Shell one-liner, run through `/bin/sh -c` from the config folder.
        var run: String?
        /// Submenu written out in place.
        var commands: [Command]?
        /// Shell one-liner whose stdout is a JSON array of commands — the submenu it opens.
        var menu: String?
        /// Typing this at the root hands the rest of the query to `run` / `menu` as `$1` — still
        /// on Enter, so the script runs once, not per keystroke.
        var prefix: String?
    }
}

extension Config {
    /// A folder under `plugins/`: `plugin.jsonc` is its manifest, and the folder is the working
    /// directory its scripts run from, so `./script.sh` inside a plugin means the plugin's own
    /// script.
    struct Plugin {
        let directory: URL
        let commands: [Command]
    }

    /// What `plugin.jsonc` holds. One key today: `commands`, the same array a `menu` prints.
    /// An object rather than the bare array, so a future key (a minimum app version, say) is an
    /// addition, not a format break.
    struct Manifest: Decodable {
        var commands: [Command]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            commands = container.value(.commands, or: [])
        }

        private enum CodingKeys: String, CodingKey { case commands }
    }
}

extension [Config.Plugin] {
    /// The command whose `prefix` starts `query`, with its plugin's directory and the rest of
    /// the query — its argument. The longest prefix wins, so a `"g"` entry does not shadow a
    /// `"gh "` one installed after it.
    func prefixed(_ query: String) -> (command: Config.Command, directory: URL, argument: String)? {
        var best: (command: Config.Command, directory: URL, argument: String)?
        for plugin in self {
            for command in plugin.commands {
                guard let prefix = command.prefix, !prefix.isEmpty,
                      prefix.count > best?.command.prefix?.count ?? 0,
                      let match = query.range(of: prefix, options: [.caseInsensitive, .anchored])
                else { continue }
                best = (command, plugin.directory, String(query[match.upperBound...]))
            }
        }
        return best
    }
}
