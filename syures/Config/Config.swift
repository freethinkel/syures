import SwiftUI

/// `~/.config/syures/config.jsonc` — JSONC: comments and trailing commas are fine.
/// Decoded with `allowsJSON5`, so looser files (unquoted keys, single quotes) still parse.
/// The file is optional; every key falls back to a default.
struct Config: Decodable {
    var hotkey: String
    var appearance: Appearance
    var commands: [Command]
    /// Name of the `themes` entry layered over `appearance`.
    var theme: String?
    var themes: [String: Appearance]

    static let url = URL(filePath: NSHomeDirectory() + "/.config/syures/config.jsonc")

    /// Working directory for `run`, so `./script.sh` means what it looks like.
    static var directory: URL { url.deletingLastPathComponent() }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        do {
            var config = try decode(data)
            // Themes decode on top of `appearance`, so a second pass is needed once the base is
            // known. ponytail: re-parsing a config-sized file is cheaper than a merge type.
            if let name = config.theme,
               let overlay = try decode(data, over: config.appearance).themes[name]
                   ?? importedThemes(over: config.appearance)[name] {
                config.appearance = overlay
            }
            return config
        } catch {
            NSLog("syures: ignoring invalid config — \(error)")
            return Config()
        }
    }

    /// Themes also come from `themes/*.jsonc`, one appearance per file, named after the file —
    /// so importing a theme is dropping a file in, with nothing to edit but `theme`.
    /// Inline `themes` win on a name clash, an explicit entry beating a dropped-in file.
    static func importedThemes(over base: Appearance) -> [String: Appearance] {
        let folder = directory.appending(path: "themes")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                  includingPropertiesForKeys: nil)) ?? []
        let decoder = decoder(over: base)
        return files.reduce(into: [:]) { themes, file in
            guard let data = try? Data(contentsOf: file) else { return }
            do {
                themes[file.deletingPathExtension().lastPathComponent] =
                    try decoder.decode(Appearance.self, from: data)
            } catch {
                NSLog("syures: ignoring theme \(file.lastPathComponent) — \(error)")
            }
        }
    }

    private static func decode(_ data: Data, over base: Appearance? = nil) throws -> Config {
        try decoder(over: base).decode(Config.self, from: data)
    }

    /// The one decoder in the app: the config and a plugin's stdout are the same schema, so they
    /// must be read the same way. `base` is the appearance an overlay layers onto.
    static func decoder(over base: Appearance? = nil) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        decoder.userInfo[.appearanceBase] = base
        return decoder
    }

    static let schemaURL = url.deletingLastPathComponent().appending(path: "config.schema.json")

    /// Rewritten on every launch: it is generated, so it always describes this build.
    static func writeSchema() {
        try? FileManager.default.createDirectory(at: schemaURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data(schema.utf8).write(to: schemaURL)
    }

    #if DEBUG
    /// A plugin prints the same `Command` shape the config holds, so one check covers both.
    static func selfCheck() {
        let json = """
        [
          { "name": "Style", "commands": [{ "name": "Dark", "run": "dark-mode on" }] },
          { "name": "Projects", "menu": "./plugins/projects ~" },
          { "name": "Google", "prefix": "g", "run": "open https://google.com" },
          { "name": "GitHub", "prefix": "gh ", "menu": "./plugins/gh-search \\"$1\\"" }
        ]
        """
        let commands = try! decoder().decode([Command].self, from: Data(json.utf8))
        assert(commands[0].commands?.first?.run == "dark-mode on")
        assert(commands[0].menu == nil)
        assert(commands[1].menu == "./plugins/projects ~")
        assert(commands[1].commands == nil)
        // A prefix takes the query over; anything else still goes to the fuzzy search.
        assert(commands.prefixed("gh swift")?.argument == "swift")
        assert(commands.prefixed("GH swift")?.command.name == "GitHub")
        assert(commands.prefixed("projects") == nil)
        // The longest prefix wins, whatever order the entries are written in.
        assert(commands.prefixed("g maps")?.command.name == "Google")
        assert(commands.prefixed("ghost")?.command.name == "Google")
    }
    #endif

    /// Drops a self-documenting config in place the first time the app runs.
    static func writeDefaultIfMissing() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data(template.utf8).write(to: url)
    }

    init() {
        hotkey = "opt+space"
        appearance = Appearance()
        commands = []
        theme = nil
        themes = [:]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = container.value(.hotkey, or: "opt+space")
        appearance = container.value(.appearance, or: Appearance())
        commands = container.value(.commands, or: [])
        theme = container.value(.theme, or: String?.none)
        themes = container.value(.themes, or: [:])
    }

    private enum CodingKeys: String, CodingKey { case hotkey, appearance, commands, theme, themes }
}

extension KeyedDecodingContainer {
    /// Missing or malformed keys fall back instead of failing the whole file.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}
