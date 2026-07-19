import AppKit
import SwiftUI
import SiftCore

@MainActor
enum ThemeManager {
    static func apply(_ mode: ThemeMode) {
        switch mode {
        case .auto:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

private func dynamicColor(_ resolve: @escaping @Sendable (Bool) -> NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return resolve(isDark)
    })
}

extension Color {
    static func ink(_ opacity: Double) -> Color {
        dynamicColor { isDark in
            (isDark ? NSColor.white : NSColor.black).withAlphaComponent(opacity)
        }
    }

    static func veil(_ opacity: Double) -> Color {
        dynamicColor { isDark in
            (isDark ? NSColor.black : NSColor.white).withAlphaComponent(opacity)
        }
    }

    static func shade(_ opacity: Double) -> Color {
        dynamicColor { isDark in
            NSColor.black.withAlphaComponent(isDark ? opacity : opacity * 0.45)
        }
    }
}
