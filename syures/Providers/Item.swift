import AppKit

// What a provider puts in the list, and what happens when it is picked. Data, not closures: the
// provider stays a pure function and its result stays `Hashable`, its own id in the list.
extension Launcher {
    enum Item: Hashable {
        /// A command written in the config: it can open a submenu, so it is not a `Provided`.
        case command(Config.Command)
        case provided(Provided)

        var name: String {
            switch self {
            case .command(let command): command.name
            case .provided(let result): result.name
            }
        }

        var subtitle: String? {
            switch self {
            case .command(let command): command.subtitle
            case .provided(let result): result.subtitle
            }
        }
    }

    /// Anything a `Provider` puts in the list. Its action is data, not a closure, so a
    /// provider stays a pure function and `Provided` stays `Hashable` — it is its own list id.
    struct Provided: Hashable {
        let name: String
        var subtitle: String? = nil
        var icon: Icon? = nil
        let action: Action
        /// Frecency key. `nil` for a result recomputed from the query — a calculation has no
        /// history worth keeping.
        var id: String? = nil

        enum Icon: Hashable {
            /// An SF Symbol, an emoji, or a Nerd Font glyph.
            case symbol(String)
            /// The file's own icon, the way an app is drawn.
            case file(URL)
        }

        enum Action: Hashable {
            case copy(String)
            case run(String)
            case open(URL)
        }
    }
}

extension Launcher.Provided.Action {
    /// Spawns and forgets: waiting would freeze the card until the process is done.
    /// `argument` is the rest of a prefixed query, and only a `run` has anywhere to put it.
    func perform(_ argument: String? = nil) {
        switch self {
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .run(let script):
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = Launcher.Provided.Action.shellArguments(script, argument)
            // `./script.sh` in a command means what it looks like: next to the config.
            process.currentDirectoryURL = Config.directory
            try? process.run()
        case .open(let url):
            NSWorkspace.shared.open(url)
        }
    }

    /// Passed to `sh` as a real positional parameter, so the query never becomes shell syntax.
    /// The `"syures"` in the middle is `$0` — `sh -c` spends it on the script name.
    nonisolated static func shellArguments(_ script: String, _ argument: String?) -> [String] {
        ["-c", script, "syures"] + (argument.map { [$0] } ?? [])
    }
}
