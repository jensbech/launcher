import AppKit
import SwiftUI
import SiftCore

@MainActor
final class SiftController {
    private let store: Store
    private var panel: SiftPanel?
    private var backdrop: BackdropWindow?
    private let viewModel: SiftViewModel

    init(store: Store) {
        self.store = store
        self.viewModel = SiftViewModel(store: store)
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
        let config = store.load()
        let screen = activeScreen()
        if let screen, config.backdropEnabled {
            showBackdrop(on: screen, intensity: config.backdropIntensity)
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
        hideBackdrop()
    }

    private func showBackdrop(on screen: NSScreen, intensity: Double) {
        backdrop?.orderOut(nil)
        let window = BackdropWindow(screenFrame: screen.frame, intensity: intensity)
        window.setFrame(screen.frame, display: false)
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 1.0
        }
        backdrop = window
    }

    private func hideBackdrop() {
        guard let window = backdrop else { return }
        backdrop = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    private func launch(_ item: AppItem) {
        hide()
        NSWorkspace.shared.open(item.url)
    }

    private func makePanel() -> SiftPanel {
        let panel = SiftPanel(rootView: SiftView(viewModel: viewModel))
        panel.onResignKey = { [weak self] in self?.hide() }
        return panel
    }

    private func positionPanel(_ panel: SiftPanel) {
        guard let screen = activeScreen() else { return }
        let frame = screen.frame
        let visible = screen.visibleFrame
        let position = store.load().panelPosition
        let edgeInsetX: CGFloat = 24
        let panelHeight = panel.frame.height

        let leftX = visible.minX + edgeInsetX + SiftPanel.width / 2
        let rightX = visible.maxX - edgeInsetX - SiftPanel.width / 2
        let xs = PanelPosition.interpolatedSteps(start: leftX, center: frame.midX, end: rightX)

        let topY = visible.minY + visible.height * 0.92
        let bottomY = visible.minY + visible.height * 0.08 + panelHeight
        let ys = PanelPosition.interpolatedSteps(start: topY, center: frame.midY + panelHeight / 2, end: bottomY)

        panel.anchor = NSPoint(x: xs[position.column], y: ys[position.row])
        panel.applyAnchor()
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
