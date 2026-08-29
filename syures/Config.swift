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
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        decoder.userInfo[.appearanceBase] = base
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
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        decoder.userInfo[.appearanceBase] = base
        return try decoder.decode(Config.self, from: data)
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
          { "name": "Projects", "menu": "./plugins/projects ~" }
        ]
        """
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let commands = try! decoder.decode([Command].self, from: Data(json.utf8))
        assert(commands[0].commands?.first?.run == "dark-mode on")
        assert(commands[0].menu == nil)
        assert(commands[1].menu == "./plugins/projects ~")
        assert(commands[1].commands == nil)
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

    // MARK: - Theme

    struct Appearance: Decodable {
        var width: CGFloat
        var cornerRadius: CGFloat
        var queryFontSize: CGFloat
        var rowFontSize: CGFloat
        /// How far down the screen the card sits, as a fraction of screen height. Also where the
        /// snap guides park it when it is dragged back home.
        var topOffset: Double
        /// Shown left of the query: an SF Symbol name, or any text (an emoji, a Nerd Font glyph).
        /// Empty hides it.
        var searchIcon: String
        /// Placeholder text in the empty query field.
        var placeholder: String
        /// Font family for the query, rows and text icons. `nil` uses the system font;
        /// an unknown family silently falls back to it too.
        var fontName: String?
        var colorScheme: ColorScheme?

        /// `nil` keeps the system material / system colors.
        var accent: Color?
        /// Tints the wash over the card: opaque at the top, gone by the bottom. `nil` picks black
        /// in dark mode and the system window background in light. `"#00000000"` turns it off.
        var background: Color?
        var foreground: Color?

        init() {
            width = 680
            cornerRadius = 16
            queryFontSize = 26
            rowFontSize = 14
            topOffset = 0.2
            fontName = nil
            searchIcon = "magnifyingglass"
            placeholder = "Search apps…"
            colorScheme = nil
            accent = nil
            background = nil
            foreground = nil
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // A theme lists only what it changes; everything else stays as the base left it.
            self = decoder.userInfo[.appearanceBase] as? Appearance ?? Appearance()
            width = container.value(.width, or: width)
            cornerRadius = container.value(.cornerRadius, or: cornerRadius)
            queryFontSize = container.value(.queryFontSize, or: queryFontSize)
            rowFontSize = container.value(.rowFontSize, or: rowFontSize)
            topOffset = container.value(.topOffset, or: topOffset)
            fontName = container.value(.fontName, or: String?.none)
            searchIcon = container.value(.searchIcon, or: searchIcon)
            placeholder = container.value(.placeholder, or: placeholder)
            colorScheme = ColorScheme(name: container.value(.colorScheme, or: String?.none))
            accent = Color(hex: container.value(.accent, or: String?.none))
            background = Color(hex: container.value(.background, or: String?.none))
            foreground = Color(hex: container.value(.foreground, or: String?.none))
        }

        /// The configured family at `size`, or the system font when none is set.
        func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            guard let fontName else { return .system(size: size, weight: weight) }
            return .custom(fontName, size: size).weight(weight)
        }

        private enum CodingKeys: String, CodingKey {
            case width, cornerRadius, queryFontSize, rowFontSize, topOffset
            case fontName = "font"
            case searchIcon, placeholder
            case colorScheme, accent, background, foreground
        }
    }

    // MARK: - Plugins

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
    }
}

private extension CodingUserInfoKey {
    /// The appearance a decoded one layers onto — unset means start from the defaults.
    static let appearanceBase = CodingUserInfoKey(rawValue: "appearanceBase")!
}

private extension KeyedDecodingContainer {
    /// Missing or malformed keys fall back instead of failing the whole file.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

private extension ColorScheme {
    init?(name: String?) {
        switch name?.lowercased() {
        case "light": self = .light
        case "dark": self = .dark
        default: return nil
        }
    }
}

private extension Color {
    /// `#RRGGBB` or `#RRGGBBAA`.
    init?(hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let bits = UInt64(text, radix: 16) else { return nil }

        let hasAlpha = text.count == 8
        let channels = (0..<(hasAlpha ? 4 : 3)).reversed().map {
            Double((bits >> UInt64($0 * 8)) & 0xFF) / 255
        }
        self.init(.sRGB, red: channels[0], green: channels[1], blue: channels[2],
                  opacity: hasAlpha ? channels[3] : 1)
    }
}

private extension Config {
    static let template = """
    {
      "$schema": "./config.schema.json",

      // Global hotkey: cmd / opt / ctrl / shift + a key. Applied at launch.
      "hotkey": "opt+space",

      "appearance": {
        "width": 680,
        "cornerRadius": 16,
        "queryFontSize": 26,
        "rowFontSize": 14,
        "topOffset": 0.2,
        // "font": "JetBrainsMono Nerd Font",
        // "searchIcon": "magnifyingglass",  // SF Symbol, or any text; "" hides it
        // "placeholder": "Search apps…",
        // "colorScheme": "dark",      // omit to follow the system
        // "accent": "#7C6CF0",
        // "background": "#1C1C1EEE",  // tints the wash over the card; "#00000000" turns it off
        // "foreground": "#FFFFFF",
      },

      // A theme lists only the appearance keys it changes; the rest stays as above.
      // Switch with a command below — one line to rewrite, nothing to duplicate.
      // Themes also load from `themes/*.jsonc` (same shape, named after the file), so an
      // imported theme is a downloaded file — see the "Import Theme" command.
      "theme": "system",
      "themes": {
        "system": {},
        "midnight": { "colorScheme": "dark", "background": "#000000", "accent": "#7C6CF0" },
        "paper": { "colorScheme": "light", "background": "#FFFFFF", "accent": "#0A84FF" },
      },

      // Plugins are entries here: `run` is a shell one-liner, so `open` and `./script.sh` work.
      "commands": [
        { "name": "Toggle System Appearance", "icon": "circle.lefthalf.filled",
          "run": "osascript -e 'tell app \\"System Events\\" to tell appearance preferences to set dark mode to not dark mode'" },
        { "name": "Import Theme", "icon": "square.and.arrow.down", "subtitle": "URL from the clipboard",
          "run": "mkdir -p themes && curl -fsSLO --output-dir themes \\"$(pbpaste)\\"" },
        { "name": "Theme", "icon": "paintpalette", "commands": [
          { "name": "System",   "run": "sed -i '' 's/\\"theme\\": \\".*\\"/\\"theme\\": \\"system\\"/' config.jsonc" },
          { "name": "Midnight", "run": "sed -i '' 's/\\"theme\\": \\".*\\"/\\"theme\\": \\"midnight\\"/' config.jsonc" },
          { "name": "Paper",    "run": "sed -i '' 's/\\"theme\\": \\".*\\"/\\"theme\\": \\"paper\\"/' config.jsonc" },
        ]},
        // { "name": "Sleep", "icon": "moon.fill", "run": "pmset sleepnow" },   // SF Symbol
        // { "name": "Files", "icon": "\u{f07b}", "run": "open ~" },              // any text works too
        // { "name": "GitHub", "icon": "globe", "run": "open https://github.com" },
        // { "name": "Style", "commands": [                        // submenu, written out here
        //   { "name": "Dark", "run": "dark-mode on" },
        // ]},
        // { "name": "Projects", "menu": "./plugins/projects ~" },  // submenu printed by a script
      ],
    }
    """
}

private extension Config {
    /// Editors pick this up through the `$schema` key in the config: key completion, type checks
    /// and typo catching (`additionalProperties: false`) for free.
    /// ponytail: hand-written and kept next to the types it describes — Swift has no schema
    /// generator worth the machinery for eleven keys
    static let schema = """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "syures config",
      "description": "Generated by syures on launch. Edits here are overwritten.",
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "$schema": { "type": "string" },
        "hotkey": {
          "type": "string",
          "default": "opt+space",
          "description": "Global hotkey: cmd / opt / ctrl / shift joined by +, then one key. Read at launch only."
        },
        "appearance": { "$ref": "#/$defs/appearance" },
        "theme": {
          "type": "string",
          "description": "Name of the themes entry layered over appearance. Omit to use appearance as-is."
        },
        "themes": {
          "type": "object",
          "description": "Named overlays: each lists only the appearance keys it changes.",
          "additionalProperties": { "$ref": "#/$defs/appearance" }
        },
        "commands": {
          "type": "array",
          "description": "Entries shown alongside installed apps.",
          "items": { "$ref": "#/$defs/command" }
        }
      },
      "$defs": {
        "color": {
          "type": "string",
          "pattern": "^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$",
          "description": "#RRGGBB or #RRGGBBAA"
        },
        "appearance": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "width": { "type": "number", "exclusiveMinimum": 0, "default": 680 },
            "cornerRadius": { "type": "number", "minimum": 0, "default": 16 },
            "queryFontSize": { "type": "number", "exclusiveMinimum": 0, "default": 26 },
            "rowFontSize": { "type": "number", "exclusiveMinimum": 0, "default": 14 },
            "topOffset": {
              "type": "number",
              "minimum": 0,
              "maximum": 1,
              "default": 0.2,
              "description": "How far down the screen the card sits, as a fraction of screen height."
            },
            "searchIcon": {
              "type": "string",
              "default": "magnifyingglass",
              "description": "Shown left of the query: an SF Symbol name, or any text (emoji, Nerd Font glyph). Empty hides it."
            },
            "placeholder": {
              "type": "string",
              "default": "Search apps…",
              "description": "Placeholder in the empty query field."
            },
            "font": {
              "type": "string",
              "description": "Font family for the query, rows and text icons. Omit for the system font; an unknown family falls back to it."
            },
            "colorScheme": {
              "enum": ["light", "dark"],
              "description": "Omit to follow the system."
            },
            "accent": {
              "allOf": [{ "$ref": "#/$defs/color" }],
              "description": "Omit to use the system accent."
            },
            "background": {
              "allOf": [{ "$ref": "#/$defs/color" }],
              "description": "Tints the wash over the card: opaque at the top, gone by the bottom. Omit for black in dark mode and the system window background in light; #00000000 turns it off."
            },
            "foreground": {
              "allOf": [{ "$ref": "#/$defs/color" }],
              "description": "Omit to use the system label colour."
            }
          }
        },
        "command": {
          "type": "object",
          "additionalProperties": false,
          "required": ["name"],
          "oneOf": [
            { "required": ["run"] },
            { "required": ["commands"] },
            { "required": ["menu"] }
          ],
          "properties": {
            "name": { "type": "string" },
            "subtitle": { "type": "string" },
            "icon": {
              "type": "string",
              "description": "SF Symbol name, or any text to draw as a glyph — a Nerd Font icon, an emoji, a letter."
            },
            "run": { "type": "string", "description": "Shell one-liner, run through /bin/sh -c from the config folder." },
            "commands": {
              "type": "array",
              "description": "Submenu written out in place.",
              "items": { "$ref": "#/$defs/command" }
            },
            "menu": {
              "type": "string",
              "description": "Shell one-liner whose stdout is a JSON array of commands — the submenu it opens. Same shape as this file, so entries can nest further."
            }
          }
        }
      }
    }
    """
}
