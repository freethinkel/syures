import AppKit

@Observable
final class Launcher {
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

    /// Anything a `ResultProvider` puts in the list. Its action is data, not a closure, so a
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

    var query = "" { didSet { search() } }
    var selected = 0

    private(set) var config = Config.load()
    private(set) var results: [Item] = []
    /// Bumped on every activation so the view can re-focus the search field.
    private(set) var activation = 0
    /// A `menu` script is still filling the level that is already on screen.
    private(set) var loading = false

    private var providers: [any Provider] = []

    /// Text after a matched `prefix` — the argument the command's script gets on Enter.
    /// `nil` means no prefix matched, so the script is run with no argument at all.
    private var argument: String?

    private struct Level {
        let title: String
        let icon: String?
        var entries: [Entry]
        /// Set on a level a `prefix` opened: the query is this script's `$1`, re-run as it changes.
        let script: String?
    }

    /// One entry per submenu the user has stepped into. Empty means the root list.
    private var stack: [Level] = []
    /// Bumped on every script run and level change, so a slow script cannot fill in a level the
    /// user has left or a query they have since edited.
    private var generation = 0
    private var pending: Task<Void, Never>?

    /// Titles of the submenus currently open, outermost first.
    var path: [String] { stack.map(\.title) }
    /// The submenu the user is in — what the field's chip shows. `nil` at the root.
    var current: (title: String, icon: String?)? { stack.last.map { ($0.title, $0.icon) } }

    init() {
        providers = Launcher.allProviders(config)
    }

    func activate() {
        config = Config.load()
        for index in providers.indices { providers[index].reload(config) }
        stack.removeAll()
        settle()
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
        remember(Launcher.frecencyID(item, in: path.joined(separator: "/")))
        switch item {
        case .provided(let result):
            switch result.action {
            case .copy(let text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            case .run(let script):
                Launcher.shell(script, nil)
            case .open(let url):
                NSWorkspace.shared.open(url)
            }
            return false
        case .command(let command):
            if let children = command.commands {
                push(command, children, script: nil)
                return true
            }
            if let script = command.menu {
                // Picked by name rather than typed as a prefix, a search plugin still opens as a
                // live level: pushing it runs the script for the empty query.
                push(command, [], script: command.prefix == nil ? nil : script)
                if command.prefix == nil { produce(script, nil) }
                return true
            }
            // A prefixed `run` gets the rest of the query as `$1`; a prefixed `menu` never gets
            // here — its level opens as soon as the prefix is typed, see `search()`.
            if let script = command.run { Launcher.shell(script, argument) }
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
        settle()
        query = ""
        return true
    }

    /// `query` is what the field shows on the new level; `nil` leaves it to the caller.
    private func push(_ command: Config.Command, _ commands: [Config.Command], script: String?, query: String? = "") {
        let menu = (path + [command.name]).joined(separator: "/")
        stack.append(Level(title: command.name, icon: command.icon,
                           entries: commands.map { Entry(.command($0), in: menu) }, script: script))
        settle()
        if let query { self.query = query }  // didSet re-runs the search against the level just pushed
    }

    /// Forgets any script still running for the level just left.
    private func settle() {
        generation += 1
        pending?.cancel()
        loading = false
    }

    /// Runs the script and fills the top level with its output — the level is already on screen
    /// with a spinner, so a slow plugin does not look like a dead panel. `delay` debounces the
    /// per-keystroke case; a run the query or level has outpaced drops its output.
    private func produce(_ script: String, _ argument: String?, after delay: Duration = .zero) {
        settle()
        loading = true
        let generation = self.generation
        pending = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let commands = await Launcher.produce(script, argument, in: Config.directory)
            guard generation == self.generation else { return }
            loading = false
            let entries = (commands ?? []).map { Entry(.command($0), in: path.joined(separator: "/")) }
            stack[stack.count - 1].entries = entries
            if stack[stack.count - 1].script == nil {
                search()  // whatever the user typed meanwhile filters the fresh list
            } else {
                // Not `search()`: on a live level that would run the script again, forever.
                results = entries.map(\.item)
                selected = 0
            }
        }
    }

    // ponytail: cancellation only skips a run that has not started; one that has runs to the end
    // and its output is dropped. Kill the process once a plugin is slow enough to be worth it.
    static func produce(_ script: String, _ argument: String?, in directory: URL) async -> [Config.Command]? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = shellArguments(script, argument)
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

    /// Passed to `sh` as a real positional parameter, so the query never becomes shell syntax.
    /// The `"syures"` in the middle is `$0` — `sh -c` spends it on the script name.
    nonisolated private static func shellArguments(_ script: String, _ argument: String?) -> [String] {
        ["-c", script, "syures"] + (argument.map { [$0] } ?? [])
    }

    private static func shell(_ script: String, _ argument: String?) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = shellArguments(script, argument)
        // `./script.sh` in a command means what it looks like: next to the config.
        process.currentDirectoryURL = Config.directory
        try? process.run()
    }

    /// The root command whose `prefix` starts `query`, and the rest of the query — its argument.
    /// The longest prefix wins, so a `"g"` entry does not shadow a `"gh "` one written after it.
    static func prefixed(_ query: String, in commands: [Config.Command]) -> (command: Config.Command, argument: String)? {
        var best: (command: Config.Command, argument: String)?
        for command in commands {
            guard let prefix = command.prefix, !prefix.isEmpty,
                  prefix.count > best?.command.prefix?.count ?? 0,
                  let match = query.range(of: prefix, options: [.caseInsensitive, .anchored])
            else { continue }
            best = (command, String(query[match.upperBound...]))
        }
        return best
    }

    private func search() {
        selected = 0
        argument = nil

        if stack.isEmpty, let match = Launcher.prefixed(query, in: config.commands) {
            // The prefix takes the query over: what follows it is an argument, not a search term.
            if let script = match.command.menu {
                // A search plugin: its level opens right away and the query becomes its `$1`.
                // The query is not touched here, inside its own `didSet`: the field is still
                // committing the text that got us here and would keep showing it. The prefix is
                // stripped on the next turn of the run loop, and that edit runs the script.
                push(match.command, [], script: script, query: nil)
                results = []
                let argument = match.argument
                DispatchQueue.main.async { self.query = argument }
                return
            }
            argument = match.argument
            results = [.command(match.command)]
            return
        }

        if let level = stack.last, let script = level.script {
            // The script does the filtering — every run is for the query as typed now.
            results = level.entries.map(\.item)
            produce(script, query, after: .milliseconds(300))
            return
        }

        if let level = stack.last {
            // A menu is authored, so an empty query keeps its order instead of showing nothing.
            results = query.isEmpty
                ? level.entries.map(\.item)
                : merge([Entry.search(level.entries, query)])
            return
        }
        guard !query.isEmpty else {
            results = []
            return
        }
        results = merge(providers.map { $0.search(query) })
    }

    /// The rows for a query in the order they are shown: score first, then frecency, then the
    /// provider's place in the registry. `groups` is one array per provider, so that place is
    /// just the index.
    private func merge(_ groups: [[Match]]) -> [Item] {
        var found = groups.enumerated().flatMap { rank, matches in matches.map { (rank, $0) } }
        // An answer to the query cancels everything that merely resembles it.
        if found.contains(where: { $0.1.exclusive }) {
            found.removeAll { !$0.1.exclusive }
        }
        let now = Date().timeIntervalSinceReferenceDate
        // Frecency only orders equally good matches, so a better match always wins — a weighted
        // bonus cannot do that, since the gaps it would have to stay under are as small as 2.
        let scored = found.map {
            ($0.0, $0.1, frecency(for: Launcher.frecencyID($0.1.item, in: path.joined(separator: "/")),
                                  now: now))
        }
        return scored.sorted {
            if $0.1.score != $1.1.score { return $0.1.score > $1.1.score }
            if $0.2 != $1.2 { return $0.2 > $1.2 }
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            return $0.1.item.name < $1.1.item.name
        }.map(\.1.item)
    }

    // MARK: - Frecency

    private static let frecencyKey = "frecency"

    /// Kind- and menu-qualified, so an app never shares a record with a command of the same name,
    /// and neither does a command with its namesake one submenu over.
    static func frecencyID(_ item: Item, in menu: String) -> String {
        switch item {
        case .command(let command): "cmd:\(menu)/\(command.name)"
        case .provided(let result): result.id ?? ""  // no id: nothing worth remembering
        }
    }

    /// `frecencyID -> [launch count, last run]`, so a familiar item leads its equally good rivals.
    /// ponytail: whole dict rewritten on every launch; it is a handful of names, not a database
    private var records: [String: [Double]] =
        UserDefaults.standard.dictionary(forKey: Launcher.frecencyKey) as? [String: [Double]] ?? [:]

    private func remember(_ id: String) {
        guard !id.isEmpty else { return }  // a calculation, not something with a history
        let count = records[id]?.first ?? 0
        records[id] = [count + 1, Date().timeIntervalSinceReferenceDate]
        UserDefaults.standard.set(records, forKey: Launcher.frecencyKey)
    }

    private func frecency(for id: String, now: TimeInterval) -> Double {
        guard let record = records[id], record.count == 2 else { return 0 }
        return Launcher.frecency(count: record[0], age: now - record[1])
    }

    /// Launch count halved every two weeks, so a burst of launches fades instead of sticking.
    static func frecency(count: Double, age: TimeInterval) -> Double {
        count * pow(0.5, age / (14 * 86400))
    }

    private enum Weight {
        static let match = 16, consecutive = 8
        static let prefix = 8, delimiter = 4, camel = 4
        static let gapOpen = 3, gapExtend = 1
        static let typo = 20
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
    static func selfCheck() {
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
        // It never outranks a better match — `ranked` sorts by score first, so the asserts above
        // hold whatever the launch history is.
        assert(frecency(count: 3, age: 0) > frecency(count: 1, age: 0))
        assert(frecency(count: 5, age: 90 * 86400) < frecency(count: 1, age: 0))
        // An answer takes the whole list: "2+2" shows the sum, not apps that resemble it.
        let launcher = Launcher()
        launcher.query = "2+2"
        assert(launcher.results == [.provided(Calculator.evaluate("2+2")!)])
        // Apps are a provider too, and theirs is an ordinary match, so it ranks with the rest.
        // `Calculator.app` ships with macOS and is in `searchPaths`.
        assert(AppsProvider.installed().contains { $0.name == "Calculator" })
        launcher.query = "calculator"
        assert(launcher.results.contains { $0.name == "Calculator" })
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

}
