import AppKit
import SwiftUI
import LauncherCore

@MainActor
final class LauncherController {
    private let store: Store
    private var panel: LauncherPanel?
    private let viewModel: LauncherViewModel

    init(store: Store) {
        self.store = store
        self.viewModel = LauncherViewModel(store: store)
        viewModel.onLaunch = { [weak self] item in self?.launch(item) }
        viewModel.onEscape = { [weak self] in self?.hide() }
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        viewModel.reload()
        _ = panel.contentViewController?.view
        panel.contentView?.layoutSubtreeIfNeeded()
        positionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.positionPanel(panel)
        }
    }

    func hide() {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
    }

    private func launch(_ item: AppItem) {
        hide()
        NSWorkspace.shared.open(item.url)
    }

    private func makePanel() -> LauncherPanel {
        let panel = LauncherPanel(rootView: LauncherView(viewModel: viewModel))
        panel.onResignKey = { [weak self] in self?.hide() }
        return panel
    }

    private func positionPanel(_ panel: LauncherPanel) {
        guard let screen = activeScreen() else { return }
        let visible = screen.visibleFrame
        let topY = visible.minY + visible.height * 0.80
        panel.anchor = NSPoint(x: visible.midX, y: topY)
        panel.applyAnchor()
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
