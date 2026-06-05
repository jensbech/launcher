import AppKit
import SwiftUI
import SiftCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: Store
    private let bookmarkStore: BookmarkStore
    private let onHotkeysChanged: () -> Void
    private let onSleepConfigChanged: () -> Void
    private let onStatusStripConfigChanged: (Bool) -> Void

    init(
        store: Store,
        bookmarkStore: BookmarkStore = BookmarkStore(),
        onHotkeysChanged: @escaping () -> Void = {},
        onSleepConfigChanged: @escaping () -> Void = {},
        onStatusStripConfigChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.bookmarkStore = bookmarkStore
        self.onHotkeysChanged = onHotkeysChanged
        self.onSleepConfigChanged = onSleepConfigChanged
        self.onStatusStripConfigChanged = onStatusStripConfigChanged
        super.init()
    }

    func show() {
        if window == nil {
            let viewModel = SettingsViewModel(
                store: self.store,
                bookmarkStore: self.bookmarkStore,
                onHotkeysChanged: self.onHotkeysChanged,
                onSleepConfigChanged: self.onSleepConfigChanged,
                onStatusStripConfigChanged: self.onStatusStripConfigChanged
            )
            let hosting = NSHostingController(rootView: SettingsView(viewModel: viewModel))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Sift Settings"
            win.styleMask = [.titled, .closable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = true
            win.backgroundColor = .clear
            win.appearance = NSAppearance(named: .darkAqua)
            win.isReleasedWhenClosed = false
            win.delegate = self
            window = win
        }
        NSApp.setActivationPolicy(.regular)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
