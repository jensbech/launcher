import AppKit
import Carbon.HIToolbox
import SiftCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var hotkeys: HotkeyManager!
    private var launcher: SiftController!
    private var bookmarks: BookmarkController!
    private var settings: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.reset()
        DebugLog.write("AppDelegate.didFinishLaunching")
        let store = Store()
        let bookmarkStore = BookmarkStore()
        launcher = SiftController(store: store)
        bookmarks = BookmarkController(store: store, bookmarkStore: bookmarkStore)
        settings = SettingsWindowController(store: store, bookmarkStore: bookmarkStore)
        menuBar = MenuBarController(
            onSettings: { [weak self] in self?.settings.show() },
            onQuit: { NSApp.terminate(nil) }
        )
        hotkeys = HotkeyManager()
        hotkeys.register(.init(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey),
            id: 1,
            label: "Cmd-Space"
        ) { [weak self] in self?.launcher.toggle() })
        hotkeys.register(.init(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey),
            id: 2,
            label: "Shift-Cmd-Space"
        ) { [weak self] in self?.bookmarks.toggle() })
        showFirstRunHintIfNeeded()
    }

    private func showFirstRunHintIfNeeded() {
        let key = "didShowSpotlightHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Free up ⌘Space"
        alert.informativeText = "Sift uses ⌘Space (apps) and ⇧⌘Space (bookmarks). macOS assigns ⌘Space to Spotlight by default. Open System Settings → Keyboard → Keyboard Shortcuts → Spotlight and turn off \"Show Spotlight search\" (or change its shortcut) so Sift's shortcuts work."
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
