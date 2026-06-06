import AppKit
import SwiftUI

@MainActor
final class ConfettiWindow: NSWindow {
    var onDismiss: (() -> Void)?

    init(screenFrame: NSRect, origin: CGPoint, seed: UInt64, duration: TimeInterval = 2.0) {
        super.init(contentRect: screenFrame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 5)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let view = ConfettiOverlay(
            triggeredAt: Date(),
            seed: seed,
            origin: origin,
            duration: duration
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: screenFrame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.25) { [weak self] in
            self?.orderOut(nil)
            self?.onDismiss?()
        }

        orderFront(nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct ConfettiOverlay: View {
    let triggeredAt: Date
    let origin: CGPoint
    let duration: TimeInterval
    let particles: [ConfettiParticle]

    private static let particleCount = 280

    init(triggeredAt: Date, seed: UInt64, origin: CGPoint, duration: TimeInterval) {
        self.triggeredAt = triggeredAt
        self.origin = origin
        self.duration = duration
        self.particles = Self.generate(seed: seed)
    }

    private static func generate(seed: UInt64) -> [ConfettiParticle] {
        var rng = ConfettiRNG(seed: seed &* 0x9E3779B97F4A7C15)
        return (0..<particleCount).map { _ in
            ConfettiParticle(
                angle: rng.nextUnit() * 2 * .pi,
                initialSpeed: 250 + CGFloat(rng.nextUnit()) * 1100,
                speedScale: 1.0 + CGFloat(rng.nextUnit()) * 0.35,
                hue: rng.nextUnit(),
                size: CGFloat(rng.nextUnit() * 7 + 4),
                spin: (rng.nextUnit() - 0.5) * 18,
                lifeOffset: rng.nextUnit() * 0.25,
                lifeScale: 0.85 + rng.nextUnit() * 0.3
            )
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { ctx in
            Canvas { gc, _ in
                let elapsed = ctx.date.timeIntervalSince(triggeredAt)
                guard elapsed >= 0, elapsed <= duration else { return }

                for p in particles {
                    let localT = (elapsed - p.lifeOffset) / (duration * p.lifeScale)
                    if localT < 0 || localT > 1 { continue }

                    let dist = p.initialSpeed * CGFloat(localT) * p.speedScale
                    let gravity: CGFloat = 1400 * CGFloat(localT * localT)
                    let x = origin.x + cos(p.angle) * dist
                    let y = origin.y + sin(p.angle) * dist + gravity
                    let alpha = max(0, 1 - localT * 1.05)
                    let s = p.size * (1 - 0.2 * CGFloat(localT))

                    let color = Color(hue: p.hue, saturation: 0.95, brightness: 1.0).opacity(alpha)
                    var path = Path(CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
                    let transform = CGAffineTransform(rotationAngle: p.spin * CGFloat(localT))
                        .concatenating(CGAffineTransform(translationX: x, y: y))
                    path = path.applying(transform)
                    gc.fill(path, with: .color(color))
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

struct ConfettiParticle {
    let angle: Double
    let initialSpeed: CGFloat
    let speedScale: CGFloat
    let hue: Double
    let size: CGFloat
    let spin: Double
    let lifeOffset: Double
    let lifeScale: Double
}

struct ConfettiRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
        return z ^ (z &>> 31)
    }
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
