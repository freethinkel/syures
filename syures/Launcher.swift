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

    /// A searchable item with its match key precomputed, so the keystroke path allocates nothing.
    private struct Entry {
        let item: Item
        let name: String
        /// `name` lowercased, as UTF-8 bytes.
        let haystack: [UInt8]
        /// Positional bonus per byte of `haystack`.
        let bonus: [Int]

        init(_ item: Item) {
            self.item = item
            name = item.name
            (haystack, bonus) = Launcher.matchKey(name)
        }
    }

    var query = "" { didSet { search() } }
    var selected = 0

    private(set) var config = Config.load()
    private(set) var results: [Item] = []
    /// Bumped on every activation so the view can re-focus the search field.
    private(set) var activation = 0

    private let apps = Launcher.installedApps().map { Entry(.app($0)) }
    private var commands: [Entry] = []

    /// One entry per submenu the user has stepped into. Empty means the root list.
    private var stack: [(title: String, entries: [Entry])] = []

    /// Titles of the submenus currently open, outermost first.
    var path: [String] { stack.map(\.title) }

    init() {
        commands = config.commands.map { Entry(.command($0)) }
    }

    func activate() {
        config = Config.load()
        commands = config.commands.map { Entry(.command($0)) }
        stack.removeAll()
        query = ""
        activation += 1
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = min(max(0, selected + delta), results.count - 1)
    }

    /// `true` means the item opened a submenu, so the panel should stay up.
    @discardableResult
    func run(_ item: Item) -> Bool {
        remember(item.name)
        switch item {
        case .app(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return false
        case .command(let command):
            if let children = command.commands {
                push(command.name, children)
                return true
            }
            if let script = command.menu {
                openMenu(command.name, script)
                return true
            }
            if let script = command.run { Launcher.shell(script) }
            return false
        }
    }

    func runSelected() -> Bool {
        guard results.indices.contains(selected) else { return false }
        return run(results[selected])
    }

    /// `false` means there is nowhere left to go back to — the caller should close the panel.
    func back() -> Bool {
        guard !stack.isEmpty else { return false }
        stack.removeLast()
        query = ""
        return true
    }

    private func push(_ title: String, _ commands: [Config.Command]) {
        stack.append((title, commands.map { Entry(.command($0)) }))
        query = ""  // didSet re-runs the search against the level just pushed
    }

    /// Runs the script and reads its stdout as the submenu to open.
    private func openMenu(_ title: String, _ script: String) {
        Task { @MainActor in
            guard let commands = await Launcher.produce(script, in: Config.directory) else { return }
            push(title, commands)
        }
    }

    // ponytail: no spinner and no cancellation — a slow script just makes the panel wait;
    // add both once a plugin takes longer than a blink
    private static func produce(_ script: String, in directory: URL) async -> [Config.Command]? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = ["-c", script]
            process.currentDirectoryURL = directory
            let pipe = Pipe()
            process.standardOutput = pipe
            do {
                try process.run()
            } catch {
                NSLog("syures: menu did not start — \(error)")
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let decoder = JSONDecoder()
            decoder.allowsJSON5 = true
            do {
                return try decoder.decode([Config.Command].self, from: data)
            } catch {
                NSLog("syures: ignoring menu output — \(error)")
                return nil
            }
        }.value
    }

    private static func shell(_ script: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]
        // `./script.sh` in a command means what it looks like: next to the config.
        process.currentDirectoryURL = Config.directory
        try? process.run()
    }

    private func search() {
        selected = 0
        let needle = Array(query.lowercased().utf8)

        if let level = stack.last {
            // A menu is authored, so an empty query keeps its order instead of showing nothing.
            results = needle.isEmpty
                ? level.entries.map(\.item)
                : ranked(needle, in: [level.entries])
            return
        }
        results = needle.isEmpty ? [] : ranked(needle, in: [commands, apps])
    }

    private func ranked(_ needle: [UInt8], in groups: [[Entry]]) -> [Item] {
        var scored: [(entry: Entry, score: Int)] = []
        for group in groups {
            for entry in group {
                if let score = Launcher.fuzzyScore(needle, entry.haystack, bonus: entry.bonus) {
                    scored.append((entry, score + bonus(for: entry.name)))
                }
            }
        }
        scored.sort { $0.score == $1.score ? $0.entry.name < $1.entry.name : $0.score > $1.score }
        return scored.map(\.entry.item)
    }

    // MARK: - Frecency

    private static let frecencyKey = "frecency"

    /// `name -> [launch count, last run]`, so a familiar item outranks its same-prefix neighbours.
    /// ponytail: whole dict rewritten on every launch; it is a handful of names, not a database
    private var frecency: [String: [Double]] =
        UserDefaults.standard.dictionary(forKey: Launcher.frecencyKey) as? [String: [Double]] ?? [:]

    private func remember(_ name: String) {
        let count = frecency[name]?.first ?? 0
        frecency[name] = [count + 1, Date().timeIntervalSinceReferenceDate]
        UserDefaults.standard.set(frecency, forKey: Launcher.frecencyKey)
    }

    private func bonus(for name: String) -> Int {
        guard let record = frecency[name], record.count == 2 else { return 0 }
        return Launcher.frecencyBonus(
            count: record[0], age: Date().timeIntervalSinceReferenceDate - record[1])
    }

    /// Launch count halved every two weeks, so a burst of launches fades instead of sticking.
    /// Capped at twice the weight: frecency breaks ties, it does not outrank a better match.
    static func frecencyBonus(count: Double, age: TimeInterval) -> Int {
        Int(Double(Weight.frecency) * min(2, count * pow(0.5, age / (14 * 86400))))
    }

    private enum Weight {
        static let match = 16, consecutive = 8
        static let prefix = 8, delimiter = 4, camel = 4
        static let gapOpen = 3, gapExtend = 1
        static let typo = 20
        static let frecency = 24
    }

    /// Lowercased UTF-8 bytes of `name` plus a positional bonus for each byte: start of the
    /// name, start of a word, start of a camelCase hump.
    /// ponytail: ASCII-only word/case detection - non-ASCII names still match, they just score flat
    static func matchKey(_ name: String) -> (haystack: [UInt8], bonus: [Int]) {
        let haystack = Array(name.lowercased().utf8)
        let raw = Array(name.utf8)
        guard raw.count == haystack.count else {  // lowercasing changed the byte length
            return (haystack, Array(repeating: 0, count: haystack.count))
        }
        let bonus = raw.indices.map { j -> Int in
            guard j > 0 else { return Weight.prefix }
            let previous = raw[j - 1]
            if " -_./".utf8.contains(previous) { return Weight.delimiter }
            if (97...122).contains(previous), (65...90).contains(raw[j]) { return Weight.camel }
            return 0
        }
        return (haystack, bonus)
    }

    /// Smith-Waterman-style alignment, the way frizbee (the matcher behind fff) scores: the
    /// needle must appear in order, and the best-scoring alignment wins - contiguous runs, word
    /// starts and camelCase humps beat the same characters scattered across the name.
    /// Returns nil when the name does not contain the needle as a subsequence.
    /// ponytail: plain O(needle x name) DP over two rows; frizbee does this in SIMD, we match ~500 names
    static func fuzzyScore(_ needle: [UInt8], _ haystack: [UInt8], bonus: [Int]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }

        // Prefilter: every needle byte must appear in the name - order ignored, so a
        // transposition still gets scored, and one byte may be missing outright (a typo).
        var pool: [UInt8: Int] = [:]
        for byte in haystack { pool[byte, default: 0] += 1 }
        var misses = 0
        for byte in needle {
            if let left = pool[byte], left > 0 { pool[byte] = left - 1 } else { misses += 1 }
        }
        guard misses <= (needle.count >= 3 ? 1 : 0) else { return nil }

        // `m[j]`: best score for an alignment whose last match is needle[i] at haystack[j].
        // `g[j]`: best score for an alignment sitting in a gap at haystack[j].
        // `d[j]`: best score for an alignment that gave up on needle[i] - one typo costs `typo`.
        let none = Int.min / 2
        var prevM = [Int](repeating: none, count: haystack.count)
        var prevG = prevM
        var prevD = prevM
        var m = prevM
        var g = prevM
        var d = prevM
        for i in needle.indices {
            for j in haystack.indices {
                let carry: Int
                if i == 0 {
                    carry = 0  // the first needle byte may start anywhere
                } else if j == 0 {
                    carry = none
                } else {
                    let contiguous = prevM[j - 1] == none ? none : prevM[j - 1] + Weight.consecutive
                    carry = max(contiguous, prevG[j - 1], prevD[j - 1])
                }
                m[j] = (haystack[j] == needle[i] && carry > none) ? carry + Weight.match + bonus[j] : none
                g[j] = j == 0 ? none : max(m[j - 1] - Weight.gapOpen, g[j - 1] - Weight.gapExtend)
                let dropped = max(prevM[j], prevD[j])
                d[j] = (i == 0 || dropped <= none) ? none : dropped - Weight.typo
            }
            swap(&prevM, &m)
            swap(&prevG, &g)
            swap(&prevD, &d)
        }

        // A typo-laden alignment can go negative; drop those instead of listing junk.
        let best = max(prevM.max() ?? none, prevD.max() ?? none)
        guard best > 0 else { return nil }
        // Mild preference for shorter names, so "chr" ranks Google Chrome over
        // Chrome Remote Desktop Host Uninstaller.
        return best - haystack.count / 4
    }

    static func fuzzyScore(_ needle: String, _ name: String) -> Int? {
        let key = matchKey(name)
        return fuzzyScore(Array(needle.lowercased().utf8), key.haystack, bonus: key.bonus)
    }

    #if DEBUG
    static func fuzzySelfCheck() {
        func score(_ needle: String, _ name: String) -> Int {
            guard let value = fuzzyScore(needle, name) else {
                assertionFailure("\(needle) should match \(name)")
                return 0
            }
            return value
        }
        assert(fuzzyScore("zzz", "Google Chrome") == nil)
        assert(fuzzyScore("chromexx", "Google Chrome") == nil)  // two stray bytes is not a typo
        assert(score("chrome", "Google Chrome") > score("chromee", "Google Chrome"))
        assert(score("xcdoe", "Xcode") > 0)  // one transposition still matches
        assert(score("safri", "Safari") > 0)
        assert(score("xcode", "Xcode") > score("xcdoe", "Xcode"))  // but clean beats typo
        assert(score("chrm", "Google Chrome") > 0)
        assert(score("почта", "Почта") > 0)  // non-ASCII still matches
        // Contiguous beats scattered, word starts beat mid-word, prefix beats everything.
        assert(score("term", "Terminal") > score("term", "Activity Monitor Terminator"))
        assert(score("saf", "Safari") > score("saf", "Sound and Fury"))
        assert(score("act", "Activity Monitor") > score("act", "Character Viewer"))
        assert(score("actmon", "Activity Monitor") > 0)  // words run together
        assert(score("am", "Amphetamine") > score("am", "Activity Monitor"))  // contiguous wins
        assert(score("chr", "Google Chrome") > score("chr", "Chrome Remote Desktop Host Uninstaller"))
        // Frecency: more launches rank higher, and an old burst decays below a fresh single run.
        assert(frecencyBonus(count: 3, age: 0) > frecencyBonus(count: 1, age: 0))
        assert(frecencyBonus(count: 5, age: 90 * 86400) < frecencyBonus(count: 1, age: 0))
        // A few launches are enough to flip a one-letter tie between neighbours.
        assert(frecencyBonus(count: 2, age: 0) > score("s", "Safari") - score("s", "Slack"))
    }
    #endif

    // ponytail: main-thread-only cache, so no lock; it can't outgrow the app list
    private static var iconCache: [String: NSImage] = [:]

    /// `NSWorkspace.icon(forFile:)` is a synchronous IconServices call — never make it from `body`.
    static func icon(for path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = image
        return image
    }

    // ponytail: main-thread-only cache, so no lock; one entry per distinct icon string
    private static var symbolCache: [String: Bool] = [:]

    /// True when the string names an SF Symbol. Anything else — a Nerd Font glyph, an emoji, a
    /// letter — is drawn as text instead, so no second config key is needed to tell them apart.
    static func isSymbol(_ name: String) -> Bool {
        if let cached = symbolCache[name] { return cached }
        let exists = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        symbolCache[name] = exists
        return exists
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
