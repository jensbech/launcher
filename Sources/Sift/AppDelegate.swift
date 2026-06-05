import AppKit
import Carbon.HIToolbox
import SiftCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var hotkeys: HotkeyManager!
    private var launcher: SiftController!
    private var bookmarks: BookmarkController!
    private var settings: SettingsWindowController!
    private var store: Store!

    private static let launcherHotkeyID: UInt32 = 1
    private static let bookmarksHotkeyID: UInt32 = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.reset()
        DebugLog.write("AppDelegate.didFinishLaunching")
        store = Store()
        let bookmarkStore = BookmarkStore()
        launcher = SiftController(store: store, onOpenSettings: { [weak self] in
            self?.settings.show()
        })
        bookmarks = BookmarkController(store: store, bookmarkStore: bookmarkStore)
        settings = SettingsWindowController(
            store: store,
            bookmarkStore: bookmarkStore,
            onHotkeysChanged: { [weak self] in self?.rebindHotkeys() },
            onSleepConfigChanged: { [weak self] in self?.menuBar.refreshTint() },
            onStatusStripConfigChanged: { enabled in
                if enabled { AudioMeterService.shared.start() } else { AudioMeterService.shared.stop() }
            }
        )
        menuBar = MenuBarController(
            store: store,
            onSettings: { [weak self] in self?.settings.show() },
            onQuit: { NSApp.terminate(nil) }
        )
        hotkeys = HotkeyManager()
        rebindHotkeys()
        SleepService.shared.startWatching()
        if store.load().statusStripEnabled {
            AudioMeterService.shared.start()
        }
        showFirstRunHintIfNeeded()
    }

    private func rebindHotkeys() {
        let config = store.load()
        hotkeys.register(.init(
            keyCode: config.launcherHotkey.keyCode,
            modifiers: config.launcherHotkey.modifiers,
            id: Self.launcherHotkeyID,
            label: "Launcher (\(config.launcherHotkey.displayString()))"
        ) { [weak self] in self?.launcher.toggle() })
        if config.combinedSearch {
            hotkeys.unregister(id: Self.bookmarksHotkeyID)
        } else {
            hotkeys.register(.init(
                keyCode: config.bookmarksHotkey.keyCode,
                modifiers: config.bookmarksHotkey.modifiers,
                id: Self.bookmarksHotkeyID,
                label: "Bookmarks (\(config.bookmarksHotkey.displayString()))"
            ) { [weak self] in self?.bookmarks.toggle() })
        }
    }

    private func showFirstRunHintIfNeeded() {
        let key = "didShowSpotlightHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Free up ⌘Space"
        alert.informativeText = "Sift uses ⌘Space (apps) and ⇧⌘Space (bookmarks) by default. macOS assigns ⌘Space to Spotlight. Open System Settings → Keyboard → Keyboard Shortcuts → Spotlight and turn off \"Show Spotlight search\" (or change its shortcut). You can also rebind Sift's shortcuts in Settings → Shortcuts."
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
