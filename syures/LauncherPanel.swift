import SwiftUI

final class LauncherPanel: NSPanel {
    /// Transparent margin around the card so its drop shadow isn't clipped by the window.
    private static let shadowMargin: CGFloat = 48
    /// The window is fixed and transparent; the card sizes itself from the config inside it.
    private static let maxCardSize = CGSize(width: 900, height: 560)

    private let launcher = Launcher()

    init() {
        let size = CGSize(width: Self.maxCardSize.width + Self.shadowMargin * 2,
                          height: Self.maxCardSize.height + Self.shadowMargin * 2)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the card draws its own, so it can be soft and offset
        hidesOnDeactivate = false
        animationBehavior = .none

        contentView = NSHostingView(rootView: LauncherView(
            launcher: launcher,
            margin: Self.shadowMargin,
            dismiss: { [weak self] in self?.hide() }
        ))
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        hide()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Becomes key without `NSApp.activate()`, so the app the user was in stays active.
    func show() {
        moveToTopOfActiveScreen()
        makeKeyAndOrderFront(nil)
        launcher.activate()
    }

    func hide() {
        orderOut(nil)
    }

    private func moveToTopOfActiveScreen() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: screen.midX - frame.width / 2,
                               y: screen.maxY - frame.height - screen.height * 0.08 + Self.shadowMargin))
    }
}
