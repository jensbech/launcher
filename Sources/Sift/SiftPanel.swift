import AppKit
import SwiftUI
import QuartzCore

final class SiftPanel: NSPanel {
    static let width: CGFloat = 560

    var onResignKey: (() -> Void)?
    var anchor: NSPoint?

    init<Content: View>(rootView: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: SiftPanel.width, height: 60),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .modalPanel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        contentViewController = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setContentSize(_ size: NSSize) {
        let target = anchoredFrame(forContentHeight: size.height)
        guard isVisible, target.size != frame.size else {
            super.setContentSize(size)
            applyAnchor()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            ctx.allowsImplicitAnimation = true
            animator().setFrame(target, display: true)
        }
    }

    func applyAnchor() {
        let target = anchoredFrame(forContentHeight: frame.height)
        setFrame(target, display: false)
    }

    private func anchoredFrame(forContentHeight height: CGFloat) -> NSRect {
        guard let anchor else {
            return NSRect(origin: frame.origin, size: NSSize(width: SiftPanel.width, height: height))
        }
        let originX = anchor.x - SiftPanel.width / 2
        let originY = anchor.y - height
        return NSRect(x: originX, y: originY, width: SiftPanel.width, height: height)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
