import Foundation

/// Where a result in the list comes from. Three shapes, because there are three costs:
///
/// - `entries()` — a list that does not depend on the query (apps). Asked once, ranked with
///   everything else, so it competes on fuzzy score and then on frecency.
/// - `immediate(_:)` — computed from the query in the same frame (calculator). Pinned above the
///   ranked list, the way Raycast puts a calculation on top.
/// - `deferred(_:)` — a subprocess or the network (a `menu` plugin). Debounced, and dropped if
///   the query moved on.
///
/// A provider implements the one it needs; the rest default to empty.
protocol ResultProvider {
    /// Typed at the root, this hands the rest of the query to the provider instead of searching.
    var prefix: String? { get }
    func entries() -> [Launcher.Provided]
    func immediate(_ query: String) -> [Launcher.Provided]
    func deferred(_ query: String) async -> [Launcher.Provided]
    /// Only paid by a provider that has a `deferred`.
    var debounce: Duration { get }
}

extension ResultProvider {
    var prefix: String? { nil }
    var debounce: Duration { .milliseconds(300) }
    func entries() -> [Launcher.Provided] { [] }
    func immediate(_ query: String) -> [Launcher.Provided] { [] }
    func deferred(_ query: String) async -> [Launcher.Provided] { [] }
}

extension Launcher {
    // ponytail: one array, no config — registration is appending to it. A Swift type cannot be
    // added without recompiling, which is what `menu` scripts are for.
    static let providers: [ResultProvider] = [Calculator(), AppsProvider()]
}
