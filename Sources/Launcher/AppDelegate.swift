import AppKit
import LauncherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var hotkey: HotkeyManager!
    private var launcher: LauncherController!
    private var settings: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = Store()
        launcher = LauncherController(store: store)
        settings = SettingsWindowController(store: store)
        menuBar = MenuBarController(
            onSettings: { [weak self] in self?.settings.show() },
            onQuit: { NSApp.terminate(nil) }
        )
        hotkey = HotkeyManager()
        hotkey.onTrigger = { [weak self] in self?.launcher.toggle() }
        hotkey.register()
        showFirstRunHintIfNeeded()
    }

    private func showFirstRunHintIfNeeded() {
        let key = "didShowSpotlightHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Free up ⌘Space"
        alert.informativeText = "Launcher uses ⌘Space. macOS assigns ⌘Space to Spotlight by default. Open System Settings → Keyboard → Keyboard Shortcuts → Spotlight and turn off \"Show Spotlight search\" (or change its shortcut) so Launcher's ⌘Space works."
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")
        NSApp.setActivationPolicy(.regular)
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
