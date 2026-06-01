import AppKit
import SwiftUI

final class BackdropWindow: NSWindow {
    private let visualView: NSVisualEffectView
    private let dimView: NSView
    private var psychedelicHost: NSHostingView<PsychedelicView>?
    private var currentEffect: PsychedelicEffect?
    private(set) var intensity: Double
    private(set) var psychedelic: Bool
    private(set) var psychedelicIntensity: Double
    private(set) var disabledPsychedelicEffects: Set<String>
    private(set) var screenFrame: NSRect

    init(screenFrame: NSRect, intensity: Double, psychedelic: Bool, psychedelicIntensity: Double, disabledPsychedelicEffects: Set<String> = []) {
        self.intensity = max(0, min(1, intensity))
        self.psychedelic = psychedelic
        self.psychedelicIntensity = max(0, min(1, psychedelicIntensity))
        self.disabledPsychedelicEffects = disabledPsychedelicEffects
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
        if psychedelic { installPsychedelic() }
    }

    func setIntensity(_ value: Double) {
        intensity = max(0, min(1, value))
        applyIntensity()
    }

    func setPsychedelicIntensity(_ value: Double) {
        psychedelicIntensity = max(0, min(1, value))
        if let host = psychedelicHost, let effect = currentEffect {
            host.rootView = PsychedelicView(intensity: psychedelicIntensity, effect: effect)
        }
    }

    func setScreenFrame(_ frame: NSRect) {
        screenFrame = frame
        setFrame(frame, display: false)
    }

    func setPsychedelicEnabled(_ enabled: Bool, intensity: Double, disabledKeys: Set<String>) {
        psychedelic = enabled
        psychedelicIntensity = max(0, min(1, intensity))
        disabledPsychedelicEffects = disabledKeys
        if enabled {
            if psychedelicHost == nil {
                installPsychedelic()
            } else {
                cyclePsychedelicEffect(disabledKeys: disabledKeys)
            }
        } else {
            removePsychedelic()
        }
    }

    func cyclePsychedelicEffect(disabledKeys: Set<String>) {
        disabledPsychedelicEffects = disabledKeys
        guard let effect = PsychedelicEffect.random(excluding: disabledKeys) else {
            removePsychedelic()
            return
        }
        currentEffect = effect
        let view = PsychedelicView(intensity: psychedelicIntensity, effect: effect)
        if let host = psychedelicHost {
            host.rootView = view
            host.frame = visualView.bounds
        } else {
            let host = NSHostingView(rootView: view)
            host.frame = visualView.bounds
            host.autoresizingMask = [.width, .height]
            visualView.addSubview(host)
            psychedelicHost = host
        }
    }

    private func installPsychedelic() {
        guard let effect = PsychedelicEffect.random(excluding: disabledPsychedelicEffects) else { return }
        currentEffect = effect
        let host = NSHostingView(rootView: PsychedelicView(intensity: psychedelicIntensity, effect: effect))
        host.frame = visualView.bounds
        host.autoresizingMask = [.width, .height]
        visualView.addSubview(host)
        psychedelicHost = host
    }

    private func removePsychedelic() {
        psychedelicHost?.removeFromSuperview()
        psychedelicHost = nil
        currentEffect = nil
    }

    private func applyIntensity() {
        visualView.alphaValue = 0.15 + 0.85 * intensity
        let dimAlpha = 0.04 + 0.32 * intensity
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(dimAlpha).cgColor
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
