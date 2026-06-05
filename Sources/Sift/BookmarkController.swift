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
        viewModel.onOpenURL = { [weak self] urlString in self?.openURL(urlString) }
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
            PanelPlacement.presentBackdrop(on: screen, intensity: config.backdropIntensity, psychedelic: config.psychedelicEnabled, psychedelicIntensity: config.psychedelicIntensity, disabledPsychedelicEffects: config.disabledPsychedelicEffects, existing: &backdrop)
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
        openURL(bookmark.url)
    }

    private func openURL(_ urlString: String) {
        hide()
        guard let url = URL(string: urlString) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            NSWorkspace.shared.open(url)
        }
    }

    private func makePanel() -> SiftPanel {
        let panel = SiftPanel(rootView: BookmarkView(viewModel: viewModel))
        panel.onResignKey = { [weak self] in self?.hide() }
        panel.onPreKeyDown = { [weak self] event in
            guard let self else { return false }
            guard event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control),
                  event.charactersIgnoringModifiers?.lowercased() == "c" else {
                return false
            }
            return self.viewModel.copySelectedURL()
        }
        return panel
    }

    private func positionPanel(_ panel: SiftPanel, position: PanelPosition? = nil) {
        guard let screen = PanelPlacement.activeScreen() else { return }
        let target = position ?? store.load().panelPosition(forScreenName: screen.localizedName)
        PanelPlacement.position(panel, position: target, on: screen)
    }
}
