import AppKit
import JavaScriptCore

/// `2.5*2` -> `= 5`, copied on Enter. Synchronous and pure, which is what lets it run on every
/// keystroke — a `menu` plugin cannot, being a `fork`/`exec`.
struct Calculator: Provider {
    func search(_ query: String) -> [Entry] {
        Calculator.evaluate(query).map { [$0] } ?? []
    }

    /// ponytail: JavaScriptCore rather than a parser or `NSExpression` — a half-typed expression
    /// returns nil here, where `NSExpression(format:)` raises an ObjC exception Swift cannot catch.
    /// `unsafe` the way `Launcher.iconCache` is: providers are pure and synchronous, so this is
    /// touched from `search()` on the main thread and nowhere else.
    nonisolated(unsafe) private static let js: JSContext = {
        let context = JSContext()!
        context.exceptionHandler = { _, _ in }  // "2+" is a work in progress, not an error
        return context
    }()

    static func evaluate(_ query: String) -> AnswerEntry? {
        let expression = query.trimmingCharacters(in: .whitespaces)
        // The whitelist is what keeps `js` an arithmetic evaluator instead of an eval box.
        guard expression.contains(where: "+-*/%".contains),
            expression.allSatisfy({ $0.isNumber || "+-*/%(). ".contains($0) }),
            // ponytail: `2024-01-15` is a date and `555-1234` a phone, not subtraction — when `-`
            // is the only operator, a space is what says "I meant math".
            expression.contains(where: "+*/%".contains) || expression.contains(" "),
            let value = js.evaluateScript(expression), value.isNumber,
            value.toDouble().isFinite
        else { return nil }
        // Significant digits, not fraction digits, or `1/100000000000` copies "0"; the fixed
        // locale keeps the copied text re-typable — the whitelist above accepts `.`, never `,`.
        let text = value.toDouble().formatted(
            .number.precision(.significantDigits(1...10)).grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX")))
        return AnswerEntry(text, of: expression)
    }

    #if DEBUG
    static func selfCheck() {
        // Providers: a result on every keystroke, nothing for a query that is not arithmetic.
        assert(evaluate("2.5*2")?.name == "= 5")
        assert(evaluate("5/2")?.text == "2.5")
        assert(evaluate("0.1+0.2")?.name == "= 0.3")
        assert(evaluate("chrome") == nil)
        assert(evaluate("2+") == nil)
        assert(evaluate("1/0") == nil)
        assert(evaluate("1/100000000000")?.text == "0.00000000001")
        assert(evaluate("2024-01-15") == nil)  // a date, not arithmetic
        assert(evaluate("555-1234") == nil)  // a phone number
        assert(evaluate("555 - 1234")?.name == "= -679")  // the space means math
    }
    #endif
}

/// The sum itself, not something whose name looks like the sum — so it takes the whole list and
/// skips the matcher, which would never find "4" in the `2+2` it came from.
final class AnswerEntry: Entry {
    /// What Enter copies.
    let text: String
    private let expression: String

    init(_ text: String, of expression: String) {
        self.text = text
        self.expression = expression
        super.init("= \(text)")
    }

    override var subtitle: String? { expression }
    override var icon: Icon? { .symbol("equal.square") }
    override var exclusive: Bool { true }
    override func score(_ needle: [UInt8]) -> Int? { 0 }

    override func run(in launcher: Launcher) -> Bool {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return false
    }
}
