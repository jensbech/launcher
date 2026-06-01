import AppKit
import SwiftUI
import SiftCore

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private let store: Store
    private var eventMonitor: Any?

    private lazy var templateMark: NSImage = {
        let img = SiftMarkImage.make(color: .black, size: 18)
        img.isTemplate = true
        img.accessibilityDescription = "Sift"
        return img
    }()
    private lazy var highlightMark: NSImage = {
        let img = SiftMarkImage.make(color: NSColor(srgbRed: 1.0, green: 0.82, blue: 0.18, alpha: 1.0), size: 18)
        img.isTemplate = false
        img.accessibilityDescription = "Sift"
        return img
    }()

    init(store: Store, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.store = store
        self.onSettings = onSettings
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        let view = StatusMenuView(
            onSettings: { [weak self] in
                self?.close()
                self?.onSettings()
            },
            onQuit: { [weak self] in
                self?.close()
                self?.onQuit()
            }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.view.frame = NSRect(x: 0, y: 0, width: StatusMenuView.size.width, height: StatusMenuView.size.height)
        popover.contentViewController = hosting
        popover.contentSize = StatusMenuView.size

        Task { @MainActor in
            SleepService.shared.onStateChange = { [weak self] in self?.refreshTint() }
            self.refreshTint()
        }
    }

    @MainActor
    func refreshTint() {
        guard let button = statusItem.button else { return }
        let config = store.load()
        let highlight = config.sleepCommandsEnabled && SleepService.shared.isDisabled
        button.image = highlight ? highlightMark : templateMark
        button.contentTintColor = nil
    }

    @objc private func toggle(_ sender: Any?) {
        if popover.isShown {
            close()
        } else {
            open()
        }
    }

    private func open() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func close() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

private struct StatusMenuView: View {
    static let size = NSSize(width: 232, height: 132)
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header()

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            VStack(spacing: 2) {
                MenuRow(
                    title: "Settings",
                    shortcut: ["⌘", ","],
                    icon: "slider.horizontal.3",
                    action: onSettings
                )
                MenuRow(
                    title: "Quit Sift",
                    shortcut: ["⌘", "Q"],
                    icon: "power",
                    accent: .red,
                    action: onQuit
                )
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .frame(width: StatusMenuView.size.width, height: StatusMenuView.size.height)
        .background(
            ZStack {
                Color.black.opacity(0.18)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.04),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
    }
}

private struct Header: View {
    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: Color.accentColor.opacity(0.8), radius: 4)
            }
            Text("SIFT")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2.6)
                .foregroundStyle(.white.opacity(0.92))

            Spacer()

            HStack(spacing: 3) {
                ShortcutChip(text: "⌘")
                ShortcutChip(text: "Space")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ShortcutChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

private struct MenuRow: View {
    let title: String
    let shortcut: [String]
    let icon: String
    var accent: Color = .accentColor
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hover ? accent.opacity(0.22) : Color.white.opacity(0.05))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hover ? accent : Color.white.opacity(0.7))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(hover ? 1 : 0.88))
                Spacer()
                HStack(spacing: 3) {
                    ForEach(shortcut, id: \.self) { key in
                        ShortcutChip(text: key)
                    }
                }
                .opacity(hover ? 1 : 0.7)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hover ? Color.white.opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
