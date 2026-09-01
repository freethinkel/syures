import SwiftUI

extension ColorScheme {
    init?(name: String?) {
        switch name?.lowercased() {
        case "light": self = .light
        case "dark": self = .dark
        default: return nil
        }
    }
}

extension Color {
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
