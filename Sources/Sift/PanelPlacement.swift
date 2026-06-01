import AppKit
import SiftCore

enum PanelPlacement {
    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    static func position(_ panel: SiftPanel, position: PanelPosition, on screen: NSScreen) {
        let frame = screen.frame
        let visible = screen.visibleFrame
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

    @MainActor
    static func presentBackdrop(on screen: NSScreen, intensity: Double, psychedelic: Bool, psychedelicIntensity: Double, disabledPsychedelicEffects: Set<String> = [], existing: inout BackdropWindow?) {
        let window: BackdropWindow
        if let cached = existing, cached.screenFrame == screen.frame {
            window = cached
            window.setIntensity(intensity)
            window.setPsychedelicEnabled(psychedelic, intensity: psychedelicIntensity, disabledKeys: disabledPsychedelicEffects)
            window.alphaValue = 0
        } else {
            existing?.orderOut(nil)
            window = BackdropWindow(screenFrame: screen.frame, intensity: intensity, psychedelic: psychedelic, psychedelicIntensity: psychedelicIntensity, disabledPsychedelicEffects: disabledPsychedelicEffects)
            window.setFrame(screen.frame, display: false)
        }
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 1.0
        }
        existing = window
    }

    @MainActor
    static func dismissBackdrop(_ existing: inout BackdropWindow?) {
        guard let window = existing else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: { [weak window] in
            guard let window, window.alphaValue == 0 else { return }
            window.orderOut(nil)
        })
    }
}
