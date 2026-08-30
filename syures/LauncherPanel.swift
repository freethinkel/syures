import SwiftUI

final class LauncherPanel: NSPanel {
    private static let shadowMargin: CGFloat = 48
    private static let maxCardSize = CGSize(width: 900, height: 560)
    private static let snapDistance: CGFloat = 14
    private static let spotsKey = "launcher.spots"

    private let launcher = Launcher()
    private let guides = GuideOverlay()

    private var dragAnchor: NSPoint?
    private var dragStart: NSPoint = .zero
    private var dragScreen: NSScreen?
    private var dragging = false
    private var snapped = (x: false, y: false)

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
            maxHeight: Self.maxCardSize.height,
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
        launcher.activate()  // reloads the config first, so placement uses the current topOffset
        setFrameOrigin(origin(on: NSScreen.main))
        makeKeyAndOrderFront(nil)
    }

    func hide() {
        endDrag()
        orderOut(nil)
    }

    // MARK: - Dragging

    /// Mouse-down in the card's header starts a window drag; the drag events themselves are
    /// swallowed so the text field doesn't also start selecting.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        // The field's editor eats Backspace before SwiftUI's `onKeyPress` sees it, so the
        // step-out-of-a-submenu case is caught here, a level up. 51 is kVK_Delete.
        case .keyDown where event.keyCode == 51 && event.modifierFlags.intersection([.command, .option, .control]).isEmpty && launcher.query.isEmpty:
            if launcher.back() { return }
        case .leftMouseDown where dragZone.contains(event.locationInWindow):
            dragAnchor = NSEvent.mouseLocation
            dragStart = frame.origin
            dragScreen = screen ?? NSScreen.main
            snapped = (false, false)
        case .leftMouseDragged where dragAnchor != nil:
            drag(to: NSEvent.mouseLocation)
            return
        case .leftMouseUp where dragAnchor != nil:
            endDrag()
        default:
            break
        }
        super.sendEvent(event)
    }

    private func drag(to mouse: NSPoint) {
        guard let anchor = dragAnchor else { return }
        var origin = NSPoint(x: dragStart.x + mouse.x - anchor.x,
                             y: dragStart.y + mouse.y - anchor.y)
        guard dragging || hypot(origin.x - dragStart.x, origin.y - dragStart.y) > 3 else { return }
        dragging = true

        // The pointer decides which screen the drag belongs to, so home and the guides follow it
        // across a monitor edge.
        dragScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? dragScreen
        guard let visible = dragScreen?.visibleFrame else { return }
        let home = defaultOrigin(in: visible)
        let hit = (x: abs(origin.x - home.x) < Self.snapDistance,
                   y: abs(origin.y - home.y) < Self.snapDistance)
        if hit.x { origin.x = home.x }
        if hit.y { origin.y = home.y }
        if (hit.x && !snapped.x) || (hit.y && !snapped.y) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
        }
        snapped = hit

        setFrameOrigin(origin)
        guides.show(on: dragScreen, at: cardEdges(for: home), snapped: snapped)
    }

    private func endDrag() {
        defer { dragAnchor = nil; dragging = false }
        guides.hide()
        guard dragging, let screen = dragScreen, let key = Self.spotKey(screen) else { return }
        // Parked back at home: forget the custom spot so this screen follows the default again.
        Self.savedSpots[key] = (snapped.x && snapped.y) ? nil : spot(of: frame.origin, on: screen)
    }

    /// The card's header strip, in window coordinates.
    /// ponytail: mirrors the search field's height in `LauncherView`; a few points off just makes
    /// the grab area slightly taller or shorter.
    private var dragZone: NSRect {
        let theme = launcher.config.appearance
        let height = theme.queryFontSize * 1.3 + 32
        return NSRect(x: (frame.width - theme.width) / 2,
                      y: frame.height - Self.shadowMargin - height,
                      width: theme.width, height: height)
    }

    // MARK: - Placement

    /// Where the panel belongs on `screen`: the spot the user parked it in there, or home.
    private func origin(on screen: NSScreen?) -> NSPoint {
        guard let screen else { return frame.origin }
        let visible = screen.visibleFrame
        guard let key = Self.spotKey(screen), let spot = Self.savedSpots[key], spot.count == 2 else {
            return defaultOrigin(in: visible)
        }
        return NSPoint(x: visible.minX + spot[0] * visible.width,
                       y: visible.minY + spot[1] * visible.height)
    }

    /// A parked position as fractions of the screen's visible frame, so the same spot survives a
    /// display of a different size or scale.
    private func spot(of origin: NSPoint, on screen: NSScreen) -> [Double] {
        let visible = screen.visibleFrame
        return [(origin.x - visible.minX) / visible.width,
                (origin.y - visible.minY) / visible.height]
    }

    private func defaultOrigin(in visible: NSRect) -> NSPoint {
        NSPoint(x: visible.midX - frame.width / 2,
                y: visible.maxY - frame.height
                    - visible.height * launcher.config.appearance.topOffset + Self.shadowMargin)
    }

    /// The card's left, right and top edges for a given window origin — what the guides trace.
    private func cardEdges(for origin: NSPoint) -> (left: CGFloat, right: CGFloat, top: CGFloat) {
        let width = launcher.config.appearance.width
        return (origin.x + (frame.width - width) / 2,
                origin.x + (frame.width + width) / 2,
                origin.y + frame.height - Self.shadowMargin)
    }

    /// One parked spot per display, so moving to another monitor does not drag the panel back to
    /// where it sat on the first one.
    /// ponytail: keyed by CGDisplayID — reconnecting displays in a different order can reassign an
    /// ID, and that screen simply falls back to home
    private static var savedSpots: [String: [Double]] {
        get { UserDefaults.standard.dictionary(forKey: spotsKey) as? [String: [Double]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: spotsKey) }
    }

    private static func spotKey(_ screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }
}

/// Screen-wide, click-through overlay drawing the launcher's home position while it is dragged.
private final class GuideOverlay: NSPanel {
    private let guides = GuideView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        contentView = guides
    }

    func show(on screen: NSScreen?, at edges: (left: CGFloat, right: CGFloat, top: CGFloat),
              snapped: (x: Bool, y: Bool)) {
        guard let screen else { return }
        setFrame(screen.frame, display: false)
        guides.edges = (edges.left - screen.frame.minX,
                        edges.right - screen.frame.minX,
                        edges.top - screen.frame.minY)
        guides.snapped = snapped
        guides.needsDisplay = true
        orderFront(nil)
    }

    func hide() { orderOut(nil) }
}

private final class GuideView: NSView {
    var edges: (left: CGFloat, right: CGFloat, top: CGFloat) = (0, 0, 0)
    var snapped = (x: false, y: false)

    override func draw(_ dirtyRect: NSRect) {
        for x in [edges.left, edges.right] {
            line(from: NSPoint(x: x, y: 0), to: NSPoint(x: x, y: bounds.maxY), active: snapped.x)
        }
        line(from: NSPoint(x: 0, y: edges.top), to: NSPoint(x: bounds.maxX, y: edges.top), active: snapped.y)
    }

    private func line(from: NSPoint, to: NSPoint, active: Bool) {
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        path.lineWidth = active ? 2 : 1
        if !active { path.setLineDash([4, 6], count: 2, phase: 0) }
        (active ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.3)).setStroke()
        path.stroke()
    }
}
