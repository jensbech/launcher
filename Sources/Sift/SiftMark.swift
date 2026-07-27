import SwiftUI
import AppKit

enum SiftMarkImage {
    static func make(color: NSColor, size: CGFloat = 18) -> NSImage {
        let pixelSize = NSSize(width: size, height: size)
        let image = NSImage(size: pixelSize, flipped: false) { rect in
            let cx = rect.midX
            let cy = rect.midY
            let dim = min(rect.width, rect.height)
            let half = dim / 2 - 0.5

            let path = NSBezierPath()
            path.move(to: NSPoint(x: cx, y: cy - half))
            path.line(to: NSPoint(x: cx + half, y: cy))
            path.line(to: NSPoint(x: cx, y: cy + half))
            path.line(to: NSPoint(x: cx - half, y: cy))
            path.close()

            let dotR: CGFloat = max(0.6, dim * 0.085)
            let spacing: CGFloat = dim * 0.21
            let positions: [NSPoint] = [
                NSPoint(x: cx,           y: cy - spacing),
                NSPoint(x: cx - spacing, y: cy),
                NSPoint(x: cx,           y: cy),
                NSPoint(x: cx + spacing, y: cy),
                NSPoint(x: cx,           y: cy + spacing)
            ]
            for p in positions {
                path.append(NSBezierPath(ovalIn: NSRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2)))
            }

            path.windingRule = .evenOdd
            color.setFill()
            path.fill()
            return true
        }
        return image
    }
}
