import SwiftUI

struct LauncherView: View {
    @Bindable var launcher: Launcher
    let margin: CGFloat
    /// Tallest the card may grow before the results start scrolling.
    let maxHeight: CGFloat
    let dismiss: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var listHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0

    private var theme: Config.Appearance { launcher.config.appearance }


    /// Gap between the card's edge and a row — and, through `contentMargins`, the gap the list
    /// keeps under the selection when arrowing past the bottom.
    private static let rowInset: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            card
                .padding(margin)
            Spacer(minLength: 0)
        }
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
        .onKeyPress(.upArrow) { launcher.move(-1); return .handled }
        .onKeyPress(.downArrow) { launcher.move(1); return .handled }
        .onKeyPress(keys: ["n", "p"]) { press in  // emacs-style ctrl+n / ctrl+p
            guard press.modifiers.contains(.control) else { return .ignored }
            launcher.move(press.key.character == "n" ? 1 : -1)
            return .handled
        }
        .onExitCommand { if !launcher.back() { dismiss() } }
        .onChange(of: launcher.activation, initial: true) { searchFocused = true }
    }

    private var card: some View {
        // The field is a sibling of the list, not an overlay on it: an overlay is capped by the
        // card's height, which is derived from the field — and the two starve each other.
        ZStack(alignment: .top) {
            results
                .mask { fade }
                .frame(height: min(headerHeight + (launcher.results.isEmpty ? 0 : listHeight + Self.rowInset * 2),
                                   maxHeight))
            header
        }
            .frame(width: theme.width)
            .opacity(headerHeight > 0 ? 1 : 0)
            .transaction { $0.animation = nil }
            .foregroundStyle(theme.foreground ?? .primary)
            .modifier(CardSurface(theme: theme, height: maxHeight))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    /// The search field floats over the list rather than sitting above it, so rows keep scrolling
    /// underneath.
    private var header: some View {
        searchField
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
    }

    /// Dissolves the list where it runs under the field instead of cutting it at an edge.
    /// ponytail: a fade, not a blur — `.ultraThinMaterial` blurs what is behind the *window*, and
    /// this one is transparent, so a material here only smears the desktop over the rows.
    private var fade: some View {
        VStack(spacing: 0) {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black.opacity(0.05), location: 0.6),
                                   .init(color: .black.opacity(0.35), location: 0.85),
                                   .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: headerHeight + Self.rowInset)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: theme.rowFontSize * 0.6)
        }
    }

    /// Which submenu is open — rofi's prompt, as a chip in the field so the field never moves.
    /// Only the innermost level: the path stays in `Launcher.path`, Backspace walks it.
    private func chip(_ level: (title: String, icon: String?)) -> some View {
        HStack(spacing: 5) {
            Glyph(name: level.icon ?? "chevron.right", size: theme.queryFontSize * 0.6, theme: theme)
            Text(level.title)
                .font(theme.font(size: theme.queryFontSize * 0.65, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((theme.accent ?? .accentColor).opacity(0.2),
                    in: .capsule)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            if let level = launcher.current {
                chip(level)
            } else if !theme.searchIcon.isEmpty {
                Glyph(name: theme.searchIcon, size: theme.queryFontSize * 0.8, theme: theme)
                    .foregroundStyle(.secondary)
            }
            TextField(theme.placeholder, text: $launcher.query)
                .textFieldStyle(.plain)
                .font(theme.font(size: theme.queryFontSize, weight: .light))
            if launcher.loading {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.accent)
            }
        }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .focused($searchFocused)
            .onSubmit {
                if !launcher.runSelected() { dismiss() }
            }
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(launcher.results.enumerated()), id: \.element) { index, item in
                        ResultRow(entry: item, isSelected: index == launcher.selected, theme: theme)
                            .id(index)
                            .onTapGesture {
                                if !launcher.run(item) { dismiss() }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Self.rowInset)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            // `safeAreaInset` does not move a ScrollView's content inside an NSHostingView, so the
            // room for the floating field is made here.
            .contentMargins(.top, headerHeight + Self.rowInset, for: .scrollContent)
            .contentMargins(.bottom, Self.rowInset, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            // No anchor: SwiftUI scrolls the least it can, so the list only moves once the
            // selection would leave the viewport.
            .onChange(of: launcher.selected) { proxy.scrollTo(launcher.selected) }
        }
    }
}

/// The card's material — Liquid Glass on macOS 26+, a plain material before it — under the wash.
private struct CardSurface: ViewModifier {
    let theme: Config.Appearance
    let height: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius)
        let washed = content.modifier(Shade(theme: theme, shape: shape, height: height))
        if #available(macOS 26, *) {
            // Glass draws its own rim and shading, so no border overlay here.
            washed.glassEffect(.clear, in: shape)
        } else {
            washed
                .background(shape.fill(.regularMaterial))
                .overlay(shape.strokeBorder(.white.opacity(0.12)))
        }
    }
}

/// Sits between the card material and its content: `background` at the top, gone by the bottom.
/// Drawn at full height and clipped, so the wash looks identical whether the card shows one
/// result or all.
private struct Shade: ViewModifier {
    let theme: Config.Appearance
    let shape: RoundedRectangle
    /// Spans the card's full height, so the wash looks the same however long the list is.
    let height: CGFloat

    @Environment(\.colorScheme) private var systemScheme

    /// Unset `background` follows the scheme: black over the dark material, the system window
    /// background over the light one.
    private var tint: Color {
        if let background = theme.background { return background }
        return (theme.colorScheme ?? systemScheme) == .dark ? .black : Color(nsColor: .windowBackgroundColor)
    }

    func body(content: Content) -> some View {
        content.background {
            Color.clear
                .overlay(alignment: .top) {
                    LinearGradient(stops: [.init(color: tint, location: 0),
                                           .init(color: tint.opacity(0.9), location: 0.35),
                                           .init(color: tint.opacity(0.45), location: 0.7),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: height)
                }
                .clipShape(shape)
        }
    }
}

private struct ResultRow: View {
    let entry: Entry
    let isSelected: Bool
    let theme: Config.Appearance

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(theme.font(size: theme.rowFontSize))
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(theme.font(size: theme.rowFontSize - 3))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(.rect)
        .background(highlight, in: .rect(cornerRadius: max(theme.cornerRadius - 8, 4)))
    }

    private var highlight: Color {
        isSelected ? (theme.accent ?? .accentColor).opacity(0.3) : .clear
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.icon {
        case .file(let url):
            Image(nsImage: Launcher.icon(for: url.path))
                .resizable()
        case .symbol(let name):
            Glyph(name: name, size: 18, theme: theme)
        }
    }
}

/// An SF Symbol when the name is one, otherwise the text itself — an emoji or a Nerd Font glyph.
private struct Glyph: View {
    let name: String
    let size: CGFloat
    let theme: Config.Appearance

    var body: some View {
        if Launcher.isSymbol(name) {
            Image(systemName: name).font(.system(size: size))
        } else {
            Text(name).font(theme.font(size: size))
        }
    }
}
