import AppKit

@Observable
final class Launcher {


    var query = "" { didSet { search() } }
    var selected = 0

    private(set) var config = Config.load()
    private(set) var results: [Entry] = []
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
        var entries: [CommandEntry]
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
        providers = Launcher.allProviders(config)
        stack.removeAll()
        settle()
        query = ""
        activation += 1
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = min(max(0, selected + delta), results.count - 1)
    }

    /// `true` means the row opened a submenu, so the panel should stay up.
    @discardableResult
    func run(_ entry: Entry) -> Bool {
        remember(entry.frecencyID)
        return entry.run(in: self)
    }

    /// What a `CommandEntry` does when it is picked: a submenu is a state the card goes into,
    /// so only the launcher can carry it out.
    func open(_ command: Config.Command) -> Bool {
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
                           entries: commands.map { CommandEntry($0, in: menu) }, script: script))
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
            let entries = (commands ?? []).map { CommandEntry($0, in: path.joined(separator: "/")) }
            stack[stack.count - 1].entries = entries
            if stack[stack.count - 1].script == nil {
                search()  // whatever the user typed meanwhile filters the fresh list
            } else {
                // Not `search()`: on a live level that would run the script again, forever.
                results = entries
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

            do {
                return try Config.decoder().decode([Config.Command].self, from: data)
            } catch {
                NSLog("syures: ignoring menu output — \(error)")
                return nil
            }
        }.value
    }


    /// Spawns and forgets: waiting would freeze the card until the process is done.
    private static func shell(_ script: String, _ argument: String?) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = shellArguments(script, argument)
        // `./script.sh` in a command means what it looks like: next to the config.
        process.currentDirectoryURL = Config.directory
        try? process.run()
    }

    /// Passed to `sh` as a real positional parameter, so the query never becomes shell syntax.
    /// The `"syures"` in the middle is `$0` — `sh -c` spends it on the script name.
    nonisolated private static func shellArguments(_ script: String, _ argument: String?) -> [String] {
        ["-c", script, "syures"] + (argument.map { [$0] } ?? [])
    }

    private func search() {
        selected = 0
        argument = nil

        if stack.isEmpty, let match = config.commands.prefixed(query) {
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
            results = [CommandEntry(match.command)]
            return
        }

        if let level = stack.last, let script = level.script {
            // The script does the filtering — every run is for the query as typed now.
            results = level.entries
            produce(script, query, after: .milliseconds(300))
            return
        }

        if let level = stack.last {
            // A menu is authored, so an empty query keeps its order instead of showing nothing.
            results = query.isEmpty ? level.entries : merge([level.entries], for: query)
            return
        }
        guard !query.isEmpty else {
            results = []
            return
        }
        results = merge(providers.map { $0.search(query) }, for: query)
    }

    /// A candidate and everything the ordering needs, so the sort reads as the rule the docs
    /// state rather than as tuple indices.
    private struct Ranked {
        let entry: Entry
        let score: Int
        let frecency: Double
        /// The provider's place in the registry — the last tie-break before the name.
        let rank: Int
    }

    /// The rows for a query in the order they are shown: score first, then frecency, then the
    /// provider's place in the registry, then the name — `groups` is one array per provider, so
    /// that place is just the index.
    func merge(_ groups: [[Entry]], for query: String) -> [Entry] {
        let needle = Array(query.lowercased().utf8)
        let now = Date().timeIntervalSinceReferenceDate
        var scored = groups.enumerated().flatMap { rank, entries in
            entries.compactMap { entry in
                entry.score(needle).map {
                    Ranked(entry: entry, score: $0,
                           frecency: frecency(for: entry.frecencyID, now: now), rank: rank)
                }
            }
        }
        // An answer to the query cancels everything that merely resembles it.
        if scored.contains(where: { $0.entry.exclusive }) {
            scored.removeAll { !$0.entry.exclusive }
        }
        // Frecency only orders equally good matches, so a better match always wins — a weighted
        // bonus cannot do that, since the gaps it would have to stay under are as small as 2.
        return scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.frecency != $1.frecency { return $0.frecency > $1.frecency }
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            return $0.entry.name < $1.entry.name
        }.map(\.entry)
    }

    // MARK: - Frecency

    private static let frecencyKey = "frecency"

    /// Kind- and menu-qualified, so an app never shares a record with a command of the same name,
    /// and neither does a command with its namesake one submenu over.
    /// `frecencyID -> [launch count, last run]`, so a familiar item leads its equally good rivals.
    /// ponytail: whole dict rewritten on every launch; it is a handful of names, not a database
    private var records: [String: [Double]] =
        UserDefaults.standard.dictionary(forKey: Launcher.frecencyKey) as? [String: [Double]] ?? [:]

    private func remember(_ id: String?) {
        guard let id else { return }  // a calculation, not something with a history
        let count = records[id]?.first ?? 0
        records[id] = [count + 1, Date().timeIntervalSinceReferenceDate]
        UserDefaults.standard.set(records, forKey: Launcher.frecencyKey)
    }

    private func frecency(for id: String?, now: TimeInterval) -> Double {
        guard let id, let record = records[id], record.count == 2 else { return 0 }
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
        // It never outranks a better match — `merge` sorts by score first, so the asserts above
        // hold whatever the launch history is.
        assert(frecency(count: 3, age: 0) > frecency(count: 1, age: 0))
        assert(frecency(count: 5, age: 90 * 86400) < frecency(count: 1, age: 0))
        // Merging, on rows made up here rather than whatever this machine has installed.
        let launcher = Launcher()
        let apps = [Entry("Nosafari"), Entry("Safari"), Entry("Salt Fixer")]
        let ranked = launcher.merge([apps], for: "saf")
        assert(ranked.count == 3 && ranked.first?.name == "Safari")  // all match, the best leads
        assert(launcher.merge([apps], for: "zzz").isEmpty)
        // An answer takes the whole list: "2+2" shows the sum, not the apps that resemble it.
        let answer = launcher.merge([[Entry("2+2 Player")], Calculator().search("2+2")], for: "2+2")
        assert(answer.map(\.name) == ["= 4"])
        // On an equal score the provider listed first wins.
        let first = Entry("Same")
        let tied = launcher.merge([[first], [Entry("Same")]], for: "same")
        assert(tied.count == 2 && tied.first === first)
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
