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
