import SwiftUI

/// `~/.config/syures/config.json`, parsed as JSON5 — comments and trailing commas are fine.
/// The file is optional; every key falls back to a default.
struct Config: Decodable {
    var hotkey: String
    var appearance: Appearance
    var commands: [Command]

    static let url = URL(filePath: NSHomeDirectory() + "/.config/syures/config.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        do {
            return try decoder.decode(Config.self, from: data)
        } catch {
            NSLog("syures: ignoring invalid config — \(error)")
            return Config()
        }
    }

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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = container.value(.hotkey, or: "opt+space")
        appearance = container.value(.appearance, or: Appearance())
        commands = container.value(.commands, or: [])
    }

    private enum CodingKeys: String, CodingKey { case hotkey, appearance, commands }

    // MARK: - Theme

    struct Appearance: Decodable {
        var width: CGFloat
        var cornerRadius: CGFloat
        var queryFontSize: CGFloat
        var rowFontSize: CGFloat
        var maxResults: Int
        var colorScheme: ColorScheme?

        /// `nil` keeps the system material / system colors.
        var accent: Color?
        var background: Color?
        var foreground: Color?

        init() {
            width = 680
            cornerRadius = 16
            queryFontSize = 26
            rowFontSize = 14
            maxResults = 8
            colorScheme = nil
            accent = nil
            background = nil
            foreground = nil
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init()
            width = container.value(.width, or: width)
            cornerRadius = container.value(.cornerRadius, or: cornerRadius)
            queryFontSize = container.value(.queryFontSize, or: queryFontSize)
            rowFontSize = container.value(.rowFontSize, or: rowFontSize)
            maxResults = container.value(.maxResults, or: maxResults)
            colorScheme = ColorScheme(name: container.value(.colorScheme, or: String?.none))
            accent = Color(hex: container.value(.accent, or: String?.none))
            background = Color(hex: container.value(.background, or: String?.none))
            foreground = Color(hex: container.value(.foreground, or: String?.none))
        }

        private enum CodingKeys: String, CodingKey {
            case width, cornerRadius, queryFontSize, rowFontSize, maxResults
            case colorScheme, accent, background, foreground
        }
    }

    // MARK: - Plugins

    /// A plugin is just an entry in the config: match it by name, then shell out or open a URL.
    struct Command: Decodable, Hashable {
        var name: String
        var subtitle: String?
        /// SF Symbol name.
        var icon: String?
        /// Shell one-liner, run through `/bin/sh -c`.
        var run: String?
        /// URL or file path handed to `NSWorkspace`.
        var open: String?
    }
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
      // Global hotkey: cmd / opt / ctrl / shift + a key. Applied at launch.
      hotkey: "opt+space",

      appearance: {
        width: 680,
        cornerRadius: 16,
        queryFontSize: 26,
        rowFontSize: 14,
        maxResults: 8,
        // colorScheme: "dark",   // omit to follow the system
        // accent: "#7C6CF0",
        // background: "#1C1C1EEE",  // omit to keep the system material
        // foreground: "#FFFFFF",
      },

      // Plugins are entries here: `run` shells out, `open` hands a URL to the system.
      commands: [
        // { name: "Sleep", icon: "moon.fill", run: "pmset sleepnow" },
        // { name: "GitHub", icon: "globe", open: "https://github.com" },
      ],
    }
    """
}
