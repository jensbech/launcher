import AppKit
import SwiftUI

@MainActor
final class MarkupWindowController: NSObject, NSWindowDelegate {
    private let image: NSImage
    private let onCommit: (NSImage) -> Void
    private let onCancel: () -> Void
    private var window: NSWindow?

    init(image: NSImage, onCommit: @escaping (NSImage) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.onCommit = onCommit
        self.onCancel = onCancel
        super.init()
    }

    func show() {
        let imageSize = image.size
        let maxWidth: CGFloat = 1100
        let maxHeight: CGFloat = 750
        let toolbarHeight: CGFloat = 50
        let aspect = imageSize.width / max(imageSize.height, 1)
        var width = min(imageSize.width, maxWidth)
        var height = width / aspect
        if height > maxHeight - toolbarHeight {
            height = maxHeight - toolbarHeight
            width = height * aspect
        }
        let contentSize = NSSize(width: width, height: height + toolbarHeight)

        let view = MarkupView(
            image: image,
            onCommit: { [weak self] annotated in self?.onCommit(annotated) },
            onCancel: { [weak self] in self?.onCancel() }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.view.frame = NSRect(origin: .zero, size: contentSize)

        let win = NSWindow(contentViewController: hosting)
        win.title = "Sift Screenshot"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.setContentSize(contentSize)
        win.center()

        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    func close() {
        window?.orderOut(nil)
        window?.delegate = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        onCancel()
    }
}
