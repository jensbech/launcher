import AppKit
import SwiftUI
import SiftCore

@MainActor
final class SiftController {
    private let store: Store
    private var panel: SiftPanel?
    private var backdrop: BackdropWindow?
    private let viewModel: SiftViewModel

    init(store: Store, onOpenSettings: @escaping () -> Void = {}) {
        self.store = store
        self.viewModel = SiftViewModel(store: store)
        viewModel.onLaunch = { [weak self] item in self?.launch(item) }
        viewModel.onEscape = { [weak self] in self?.hide() }
        viewModel.onDeviceActivated = { [weak self] in self?.hide() }
        viewModel.onOpenSettings = { [weak self] in
            self?.hide()
            onOpenSettings()
        }
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
        if let hostingView = panel.contentViewController?.view {
            let fitting = hostingView.fittingSize
            if fitting.width > 0, fitting.height > 0, fitting != panel.frame.size {
                panel.setContentSize(fitting)
            }
        }
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

    private func launch(_ item: AppItem) {
        hide()
        let url = item.url
        DispatchQueue.global(qos: .userInitiated).async {
            NSWorkspace.shared.open(url)
        }
    }

    private func makePanel() -> SiftPanel {
        let panel = SiftPanel(rootView: SiftView(viewModel: viewModel))
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
