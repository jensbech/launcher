import AppKit
import SwiftUI

final class BackdropWindow: NSWindow {
    private let visualView: NSVisualEffectView
    private let dimView: NSView
    private(set) var intensity: Double
    private(set) var screenFrame: NSRect

    init(screenFrame: NSRect, intensity: Double) {
        self.intensity = max(0, min(1, intensity))
        self.screenFrame = screenFrame

        let bounds = NSRect(origin: .zero, size: screenFrame.size)
        let visual = NSVisualEffectView(frame: bounds)
        visual.material = .fullScreenUI
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.autoresizingMask = [.width, .height]

        let dim = NSView(frame: bounds)
        dim.wantsLayer = true
        dim.autoresizingMask = [.width, .height]
        visual.addSubview(dim)

        self.visualView = visual
        self.dimView = dim

        super.init(contentRect: screenFrame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        alphaValue = 0
        contentView = visual

        applyIntensity()
    }

    func setIntensity(_ value: Double) {
        intensity = max(0, min(1, value))
        applyIntensity()
    }

    func setScreenFrame(_ frame: NSRect) {
        screenFrame = frame
        setFrame(frame, display: false)
    }

    private func applyIntensity() {
        visualView.alphaValue = 0.15 + 0.85 * intensity
        let dimAlpha = 0.04 + 0.32 * intensity
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(dimAlpha).cgColor
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
