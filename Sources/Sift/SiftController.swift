import AppKit
import SwiftUI
import SiftCore

@MainActor
final class SiftController {
    private let store: Store
    private var panel: SiftPanel?
    private var backdrop: BackdropWindow?
    private let viewModel: SiftViewModel

    private var confettiWindows: [ConfettiWindow] = []

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
        viewModel.onLogoTap = { [weak self] in
            self?.triggerConfetti()
        }
    }

    private func triggerConfetti() {
        guard let panel = panel, panel.isVisible, let screen = panel.screen else { return }
        let panelFrame = panel.frame
        let screenFrame = screen.frame
        let logoCocoaX = panelFrame.minX + 32
        let logoCocoaY = panelFrame.maxY - 26
        let swiftX = logoCocoaX - screenFrame.minX
        let swiftY = screenFrame.maxY - logoCocoaY

        let win = ConfettiWindow(
            screenFrame: screenFrame,
            origin: CGPoint(x: swiftX, y: swiftY),
            seed: UInt64.random(in: 0..<UInt64.max)
        )
        confettiWindows.append(win)
        win.onDismiss = { [weak self, weak win] in
            self?.confettiWindows.removeAll { $0 === win }
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
        let config = store.load()
        let screen = PanelPlacement.activeScreen()
        if let screen, config.backdropEnabled {
            PanelPlacement.presentBackdrop(on: screen, intensity: config.backdropIntensity, psychedelic: config.psychedelicEnabled, psychedelicIntensity: config.psychedelicIntensity, disabledPsychedelicEffects: config.disabledPsychedelicEffects, existing: &backdrop)
        }
        positionPanel(panel, position: config.panelPosition)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.positionPanel(panel, position: config.panelPosition)
        }
    }

    func hide() {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        PanelPlacement.dismissBackdrop(&backdrop)
    }

    private func launch(_ item: AppItem) {
        hide()
        NSWorkspace.shared.open(item.url)
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
        let target = position ?? store.load().panelPosition
        PanelPlacement.position(panel, position: target, on: screen)
    }
}
