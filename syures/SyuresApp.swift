import SwiftUI

@main
struct SyuresApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panel = LauncherPanel()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Config.writeDefaultIfMissing()

        // Carbon registration is one-shot, so the hotkey is read at launch only.
        let combo = HotKey.Combo(Config.load().hotkey) ?? .optionSpace
        hotKey = HotKey(combo) { [panel] in panel.toggle() }

        panel.show()
    }
}
