import SwiftUI

struct LauncherView: View {
    @Bindable var launcher: Launcher
    let margin: CGFloat
    let dismiss: () -> Void

    @FocusState private var searchFocused: Bool

    private var theme: Config.Appearance { launcher.config.appearance }

    var body: some View {
        VStack(spacing: 0) {
            card
                .frame(width: theme.width)
                .padding(margin)
            Spacer(minLength: 0)
        }
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
        .onKeyPress(.upArrow) { launcher.move(-1); return .handled }
        .onKeyPress(.downArrow) { launcher.move(1); return .handled }
        .onExitCommand(perform: dismiss)
        .onChange(of: launcher.activation, initial: true) { searchFocused = true }
    }

    private var card: some View {
        VStack(spacing: 0) {
            searchField
            if !launcher.results.isEmpty {
                Divider()
                results
            }
        }
        .foregroundStyle(theme.foreground ?? .primary)
        .background(cardBackground)
        .overlay(shape.strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if let background = theme.background {
            shape.fill(background)
        } else {
            shape.fill(.regularMaterial)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.cornerRadius)
    }

    private var searchField: some View {
        TextField("Search apps…", text: $launcher.query)
            .textFieldStyle(.plain)
            .font(.system(size: theme.queryFontSize, weight: .light))
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .focused($searchFocused)
            .onSubmit {
                launcher.runSelected()
                dismiss()
            }
    }

    private var results: some View {
        VStack(spacing: 2) {
            ForEach(Array(launcher.results.enumerated()), id: \.element) { index, item in
                ResultRow(item: item, isSelected: index == launcher.selected, theme: theme)
                    .onTapGesture {
                        launcher.run(item)
                        dismiss()
                    }
            }
        }
        .padding(8)
    }
}

private struct ResultRow: View {
    let item: Launcher.Item
    let isSelected: Bool
    let theme: Config.Appearance

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: theme.rowFontSize))
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: theme.rowFontSize - 3))
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
        switch item {
        case .app(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        case .command(let command):
            Image(systemName: command.icon ?? "terminal")
                .font(.system(size: 18))
        }
    }
}
