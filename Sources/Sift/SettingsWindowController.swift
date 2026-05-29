import AppKit
import SwiftUI
import SiftCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: Store
    private let bookmarkStore: BookmarkStore

    init(store: Store, bookmarkStore: BookmarkStore = BookmarkStore()) {
        self.store = store
        self.bookmarkStore = bookmarkStore
        super.init()
    }

    func show() {
        if window == nil {
            let viewModel = SettingsViewModel(store: self.store, bookmarkStore: self.bookmarkStore)
            let hosting = NSHostingController(rootView: SettingsView(viewModel: viewModel))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Sift Settings"
            win.styleMask = [.titled, .closable]
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
