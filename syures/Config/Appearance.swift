import SwiftUI

extension Config {
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
}

extension CodingUserInfoKey {
    /// The appearance a decoded one layers onto — unset means start from the defaults.
    static let appearanceBase = CodingUserInfoKey(rawValue: "appearanceBase")!
}
