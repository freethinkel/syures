import AppKit

@Observable
final class Launcher {
    enum Item: Hashable {
        case app(URL)
        case command(Config.Command)

        var name: String {
            switch self {
            case .app(let url): url.deletingPathExtension().lastPathComponent
            case .command(let command): command.name
            }
        }

        var subtitle: String? {
            switch self {
            case .app: nil
            case .command(let command): command.subtitle
            }
        }
    }

    var query = "" { didSet { search() } }
    var selected = 0

    private(set) var config = Config.load()
    private(set) var results: [Item] = []
    /// Bumped on every activation so the view can re-focus the search field.
    private(set) var activation = 0

    private let apps = Launcher.installedApps()

    func activate() {
        config = Config.load()
        query = ""
        activation += 1
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = min(max(0, selected + delta), results.count - 1)
    }

    func run(_ item: Item) {
        switch item {
        case .app(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case .command(let command):
            if let open = command.open, let url = URL(string: open) {
                NSWorkspace.shared.open(url)
            }
            if let script = command.run {
                let process = Process()
                process.executableURL = URL(filePath: "/bin/sh")
                process.arguments = ["-c", script]
                try? process.run()
            }
        }
    }

    func runSelected() {
        guard results.indices.contains(selected) else { return }
        run(results[selected])
    }

    private func search() {
        selected = 0
        let needle = query.lowercased()
        guard !needle.isEmpty else {
            results = []
            return
        }
        let items = config.commands.map(Item.command) + apps.map(Item.app)
        results = items
            .filter { $0.name.lowercased().contains(needle) }
            .sorted { a, b in
                let aPrefix = a.name.lowercased().hasPrefix(needle)
                let bPrefix = b.name.lowercased().hasPrefix(needle)
                return aPrefix == bPrefix ? a.name < b.name : aPrefix
            }
            .prefix(config.appearance.maxResults)
            .map { $0 }
    }

    private static let searchPaths = [
        "/Applications", "/Applications/Utilities",
        "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    // ponytail: flat scan once at launch; add an FSEvents watcher if apps get installed mid-session
    private static func installedApps() -> [URL] {
        searchPaths
            .flatMap { path -> [URL] in
                let contents = try? FileManager.default.contentsOfDirectory(
                    at: URL(filePath: path), includingPropertiesForKeys: nil)
                return contents ?? []
            }
            .filter { $0.pathExtension == "app" }
    }
}
