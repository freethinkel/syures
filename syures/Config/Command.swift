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

extension [Config.Command] {
    /// The command whose `prefix` starts `query`, and the rest of the query — its argument.
    /// The longest prefix wins, so a `"g"` entry does not shadow a `"gh "` one written after it.
    func prefixed(_ query: String) -> (command: Config.Command, argument: String)? {
        var best: (command: Config.Command, argument: String)?
        for command in self {
            guard let prefix = command.prefix, !prefix.isEmpty,
                  prefix.count > best?.command.prefix?.count ?? 0,
                  let match = query.range(of: prefix, options: [.caseInsensitive, .anchored])
            else { continue }
            best = (command, String(query[match.upperBound...]))
        }
        return best
    }
}
