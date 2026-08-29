import SwiftUI
import AppKit

struct ContentView: View {
    @State private var panelController: NSWindowController? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("Main ContentView")
                .font(.title2)

            Button("Toggle Inspector Panel") {
                togglePanel()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
        .padding()
    }
}

// MARK: - Panel Management
private extension ContentView {
    func togglePanel() {
        if let window = panelController?.window, window.isVisible {
            window.orderOut(nil)
            return
        }
        showPanel()
    }

    func showPanel() {
        // Build SwiftUI content for the panel
        let panelView = PanelContentView()
        let host = NSHostingController(rootView: panelView)

        // Create the NSPanel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .utilityWindow, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.level = .floating
        panel.title = "Inspector"
        panel.contentViewController = host
        panel.center()
        panel.setFrameAutosaveName("InspectorPanelFrame")

        let controller = NSWindowController(window: panel)
        self.panelController = controller

        controller.showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI content displayed inside the panel
private struct PanelContentView: View {
    @State private var sliderValue: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.headline)
            Divider()
            HStack {
                Text("Opacity")
                Slider(value: $sliderValue, in: 0...1)
            }
            Text(String(format: "%.0f%%", sliderValue * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(minWidth: 280, minHeight: 200)
    }
}
