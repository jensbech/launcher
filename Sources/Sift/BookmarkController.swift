import AppKit
import SwiftUI
import SiftCore

@MainActor
final class BookmarkController {
    private let store: Store
    private var panel: SiftPanel?
    private var backdrop: BackdropWindow?
    private let viewModel: BookmarkViewModel

    init(store: Store, bookmarkStore: BookmarkStore = BookmarkStore()) {
        self.store = store
        self.viewModel = BookmarkViewModel(store: store, bookmarkStore: bookmarkStore)
        viewModel.onOpen = { [weak self] bookmark in self?.open(bookmark) }
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
        let config = store.load()
        let screen = PanelPlacement.activeScreen()
        if let screen, config.backdropEnabled {
            PanelPlacement.presentBackdrop(on: screen, intensity: config.backdropIntensity, existing: &backdrop)
        }
        positionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.positionPanel(panel)
        }
    }

    func hide() {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        PanelPlacement.dismissBackdrop(&backdrop)
    }

    private func open(_ bookmark: Bookmark) {
        hide()
        guard let url = URL(string: bookmark.url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func makePanel() -> SiftPanel {
        let panel = SiftPanel(rootView: BookmarkView(viewModel: viewModel))
        panel.onResignKey = { [weak self] in self?.hide() }
        return panel
    }

    private func positionPanel(_ panel: SiftPanel) {
        guard let screen = PanelPlacement.activeScreen() else { return }
        PanelPlacement.position(panel, position: store.load().panelPosition, on: screen)
    }
}
