import AppKit
import SwiftUI

final class LauncherPanel: NSPanel {
    static let width: CGFloat = 560

    var onResignKey: (() -> Void)?
    var anchor: NSPoint?

    init<Content: View>(rootView: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: LauncherPanel.width, height: 60),
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
        super.setContentSize(size)
        applyAnchor()
    }

    func applyAnchor() {
        guard let anchor else { return }
        let width = LauncherPanel.width
        let originX = anchor.x - width / 2
        let originY = anchor.y - frame.height
        setFrame(NSRect(x: originX, y: originY, width: width, height: frame.height), display: false)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
