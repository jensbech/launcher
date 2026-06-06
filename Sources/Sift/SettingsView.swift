import SwiftUI
import AppKit
import SiftCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var disabled: Set<String> = []
    @Published var filter: String = ""
    @Published var launchAtLogin: Bool = false
    @Published var panelPosition: PanelPosition = .topCenter
    @Published var perScreenPanelPositions: [String: PanelPosition] = [:]
    @Published var connectedScreenNames: [String] = []
    @Published var selectedScreenContext: String? = nil
    @Published var backdropEnabled: Bool = false
    @Published var backdropIntensity: Double = Config.defaultBackdropIntensity
    @Published var psychedelicEnabled: Bool = false
    @Published var psychedelicIntensity: Double = Config.defaultPsychedelicIntensity
    @Published var disabledPsychedelicEffects: Set<String> = []
    @Published var includeZenBookmarks: Bool = true
    @Published var includeFirefoxBookmarks: Bool = false
    @Published var managedBookmarks: [Bookmark] = []
    @Published var launcherHotkey: Hotkey = .defaultLauncher
    @Published var bookmarksHotkey: Hotkey = .defaultBookmarks
    @Published var combinedSearch: Bool = false
    @Published var devicesEnabled: Bool = false
    @Published var statusStripEnabled: Bool = false
    @Published var audioSwitcherEnabled: Bool = true
    @Published var disabledDeviceIDs: Set<String> = []
    @Published var pairedDevices: [DeviceItem] = []
    @Published var sleepCommandsEnabled: Bool = false
    @Published var sudoersConfigured: Bool = false
    @Published var screenshotEnabled: Bool = false

    private let store: Store
    private let bookmarkStore: BookmarkStore
    private var pendingPersist: DispatchWorkItem?
    private let onHotkeysChanged: () -> Void
    private let onSleepConfigChanged: () -> Void
    private let onStatusStripConfigChanged: (Bool) -> Void

    init(
        store: Store,
        bookmarkStore: BookmarkStore = BookmarkStore(),
        onHotkeysChanged: @escaping () -> Void = {},
        onSleepConfigChanged: @escaping () -> Void = {},
        onStatusStripConfigChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.bookmarkStore = bookmarkStore
        self.onHotkeysChanged = onHotkeysChanged
        self.onSleepConfigChanged = onSleepConfigChanged
        self.onStatusStripConfigChanged = onStatusStripConfigChanged
        let config = store.load()
        self.disabled = config.disabledBundleIDs
        self.launchAtLogin = config.launchAtLogin
        self.panelPosition = config.panelPosition
        self.perScreenPanelPositions = config.perScreenPanelPositions
        self.connectedScreenNames = NSScreen.screens.compactMap { $0.localizedName }
        self.backdropEnabled = config.backdropEnabled
        self.backdropIntensity = config.backdropIntensity
        self.psychedelicEnabled = config.psychedelicEnabled
        self.psychedelicIntensity = config.psychedelicIntensity
        self.disabledPsychedelicEffects = config.disabledPsychedelicEffects
        self.includeZenBookmarks = config.includeZenBookmarks
        self.includeFirefoxBookmarks = config.includeFirefoxBookmarks
        self.launcherHotkey = config.launcherHotkey
        self.bookmarksHotkey = config.bookmarksHotkey
        self.combinedSearch = config.combinedSearch
        self.devicesEnabled = config.devicesEnabled
        self.statusStripEnabled = config.statusStripEnabled
        self.audioSwitcherEnabled = config.audioSwitcherEnabled
        self.disabledDeviceIDs = config.disabledDeviceIDs
        self.sleepCommandsEnabled = config.sleepCommandsEnabled
        self.sudoersConfigured = FileManager.default.fileExists(atPath: "/etc/sudoers.d/sift")
        self.screenshotEnabled = config.screenshotEnabled
        self.managedBookmarks = bookmarkStore.load()
        self.apps = []
        Task.detached(priority: .utility) {
            let scanned = AppIndex.scan(directories: AppIndex.defaultSearchPaths)
            await MainActor.run { self.apps = scanned }
        }
        if !self.sudoersConfigured {
            Task.detached(priority: .utility) {
                let available = SettingsViewModel.sudoersRuleAvailable()
                await MainActor.run { [weak self] in self?.sudoersConfigured = available }
            }
        }
    }

    func refreshPairedDevices() {
        pairedDevices = BluetoothService.pairedDevices()
    }

    func setDevicesEnabled(_ value: Bool) {
        devicesEnabled = value
        persist()
    }

    func setAudioSwitcherEnabled(_ value: Bool) {
        audioSwitcherEnabled = value
        persist()
    }

    func setStatusStripEnabled(_ value: Bool) {
        statusStripEnabled = value
        persist()
        onStatusStripConfigChanged(value)
    }

    func setSleepCommandsEnabled(_ value: Bool) {
        sleepCommandsEnabled = value
        persist()
        onSleepConfigChanged()
    }

    func setScreenshotEnabled(_ value: Bool) {
        screenshotEnabled = value
        persist()
    }

    func refreshSudoersStatus() {
        if FileManager.default.fileExists(atPath: "/etc/sudoers.d/sift") {
            sudoersConfigured = true
            return
        }
        Task.detached(priority: .utility) {
            let available = SettingsViewModel.sudoersRuleAvailable()
            await MainActor.run { [weak self] in self?.sudoersConfigured = available }
        }
    }

    nonisolated static func sudoersRuleAvailable() -> Bool {
        if FileManager.default.fileExists(atPath: "/etc/sudoers.d/sift") {
            return true
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "-l", "/usr/bin/pmset", "disablesleep", "1"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    func isDeviceEnabled(_ device: DeviceItem) -> Bool {
        !disabledDeviceIDs.contains(device.id)
    }

    func toggleDevice(_ device: DeviceItem) {
        if disabledDeviceIDs.contains(device.id) {
            disabledDeviceIDs.remove(device.id)
        } else {
            disabledDeviceIDs.insert(device.id)
        }
        persist()
    }

    var filtered: [AppItem] {
        guard !filter.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    func isEnabled(_ item: AppItem) -> Bool { !disabled.contains(item.id) }

    func toggle(_ item: AppItem) {
        if disabled.contains(item.id) {
            disabled.remove(item.id)
        } else {
            disabled.insert(item.id)
        }
        persist()
    }

    func setLaunchAtLogin(_ value: Bool) {
        launchAtLogin = value
        LoginItem.setEnabled(value)
        persist()
    }

    func setPanelPosition(_ value: PanelPosition) {
        panelPosition = value
        persist()
    }

    func panelPosition(forContext name: String?) -> PanelPosition {
        if let name, let pos = perScreenPanelPositions[name] {
            return pos
        }
        return panelPosition
    }

    func setPanelPosition(forContext name: String?, value: PanelPosition) {
        if let name {
            perScreenPanelPositions[name] = value
        } else {
            panelPosition = value
        }
        persist()
    }

    func clearPanelPosition(forContext name: String) {
        perScreenPanelPositions.removeValue(forKey: name)
        persist()
    }

    func refreshConnectedScreens() {
        connectedScreenNames = NSScreen.screens.compactMap { $0.localizedName }
    }

    func setBackdropEnabled(_ value: Bool) {
        backdropEnabled = value
        persist()
    }

    func setBackdropIntensity(_ value: Double) {
        backdropIntensity = max(0, min(1, value))
        persistDebounced()
    }

    func setPsychedelicEnabled(_ value: Bool) {
        psychedelicEnabled = value
        persist()
    }

    func setPsychedelicIntensity(_ value: Double) {
        psychedelicIntensity = max(0, min(1, value))
        persistDebounced()
    }

    func setPsychedelicEffectEnabled(_ key: String, enabled: Bool) {
        if enabled {
            disabledPsychedelicEffects.remove(key)
        } else {
            disabledPsychedelicEffects.insert(key)
        }
        persist()
    }

    func setIncludeZenBookmarks(_ value: Bool) {
        includeZenBookmarks = value
        persist()
    }

    func setIncludeFirefoxBookmarks(_ value: Bool) {
        includeFirefoxBookmarks = value
        persist()
    }

    func setLauncherHotkey(_ value: Hotkey) {
        launcherHotkey = value
        persist()
        onHotkeysChanged()
    }

    func setBookmarksHotkey(_ value: Hotkey) {
        bookmarksHotkey = value
        persist()
        onHotkeysChanged()
    }

    func resetHotkeys() {
        launcherHotkey = .defaultLauncher
        bookmarksHotkey = .defaultBookmarks
        persist()
        onHotkeysChanged()
    }

    func setCombinedSearch(_ value: Bool) {
        combinedSearch = value
        persist()
        onHotkeysChanged()
    }

    func addBookmark(name: String, url: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }
        let normalized = trimmedURL.contains("://") ? trimmedURL : "https://\(trimmedURL)"
        managedBookmarks.append(Bookmark(name: trimmedName, url: normalized, source: .managed))
        persistBookmarks()
    }

    func removeBookmark(id: String) {
        managedBookmarks.removeAll { $0.id == id }
        persistBookmarks()
    }

    private func persistDebounced() {
        pendingPersist?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.persist() }
        pendingPersist = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func persist() {
        pendingPersist?.cancel()
        pendingPersist = nil
        store.save(Config(
            disabledBundleIDs: disabled,
            launchAtLogin: launchAtLogin,
            panelPosition: panelPosition,
            perScreenPanelPositions: perScreenPanelPositions,
            backdropEnabled: backdropEnabled,
            backdropIntensity: backdropIntensity,
            psychedelicEnabled: psychedelicEnabled,
            psychedelicIntensity: psychedelicIntensity,
            disabledPsychedelicEffects: disabledPsychedelicEffects,
            includeZenBookmarks: includeZenBookmarks,
            includeFirefoxBookmarks: includeFirefoxBookmarks,
            launcherHotkey: launcherHotkey,
            bookmarksHotkey: bookmarksHotkey,
            combinedSearch: combinedSearch,
            devicesEnabled: devicesEnabled,
            audioSwitcherEnabled: audioSwitcherEnabled,
            statusStripEnabled: statusStripEnabled,
            disabledDeviceIDs: disabledDeviceIDs,
            sleepCommandsEnabled: sleepCommandsEnabled,
            screenshotEnabled: screenshotEnabled
        ))
    }

    private func persistBookmarks() {
        bookmarkStore.save(managedBookmarks)
    }
}

private enum SettingsSection: Int, CaseIterable, Identifiable {
    case apps, bookmarks, devices, position, shortcuts, general

    var id: Int { rawValue }

    var index: String { String(format: "%02d", rawValue + 1) }

    var title: String {
        switch self {
        case .apps: return "Apps"
        case .bookmarks: return "Bookmarks"
        case .devices: return "Devices"
        case .position: return "Position"
        case .shortcuts: return "Shortcuts"
        case .general: return "General"
        }
    }

    var subtitle: String {
        switch self {
        case .apps: return "Choose which apps are searchable from the launcher."
        case .bookmarks: return "Pin URLs and merge browser bookmarks into Sift."
        case .devices: return "Show a status strip and/or search Bluetooth and audio outputs from the launcher."
        case .position: return "Pick where the launcher panel appears on screen."
        case .shortcuts: return "Rebind the global hotkeys that summon Sift."
        case .general: return "Behavior, startup, and the optional backdrop."
        }
    }
}

private enum Palette {
    static let surface = Color.black.opacity(0.18)
    static let card = Color.white.opacity(0.045)
    static let cardStroke = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.08)
    static let subtle = Color.white.opacity(0.55)
    static let muted = Color.white.opacity(0.42)
    static let dim = Color.white.opacity(0.28)
}

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    @State private var section: SettingsSection = .apps

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section)
                .frame(width: 220)

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1)

            ContentPane(section: section, viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 640)
        .background(SettingsBackdrop())
        .preferredColorScheme(.dark)
    }
}

private struct SettingsBackdrop: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.accentColor.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 520
            )
            .blendMode(.plusLighter)
            .opacity(0.55)
        }
        .ignoresSafeArea()
    }
}

private struct Sidebar: View {
    @Binding var section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader()
                .padding(.horizontal, 22)
                .padding(.top, 34)
                .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsSection.allCases) { item in
                    SidebarRow(
                        item: item,
                        selected: section == item,
                        onSelect: { section = item }
                    )
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            Footer()
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct BrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.accentColor.opacity(0.7), radius: 4)
                Text("SIFT")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(.white)
            }
            Text("Settings")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(.white.opacity(0.95))
                .italic()
        }
    }
}

private struct SidebarRow: View {
    let item: SettingsSection
    let selected: Bool
    let onSelect: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Rectangle()
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(width: 2, height: 18)

                Text(item.index)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(selected ? Color.accentColor : Palette.muted)
                    .frame(width: 22, alignment: .leading)

                Text(item.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : Palette.subtle)

                Spacer()
            }
            .padding(.vertical, 9)
            .padding(.trailing, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.05) : (hover ? Color.white.opacity(0.03) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}

private struct Footer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .padding(.bottom, 14)

            HStack(spacing: 6) {
                Image(systemName: "command")
                    .font(.system(size: 9, weight: .semibold))
                Text("Space")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundStyle(Palette.subtle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 1)
            )

            Text("Opens the launcher.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.dim)
        }
    }
}

private struct ContentPane: View {
    let section: SettingsSection
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(section: section)
                .padding(.horizontal, 36)
                .padding(.top, 38)
                .padding(.bottom, 22)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .apps: AppsPane(viewModel: viewModel)
                    case .bookmarks: BookmarksPane(viewModel: viewModel)
                    case .devices: DevicesPane(viewModel: viewModel)
                    case .position: PositionPane(viewModel: viewModel)
                    case .shortcuts: ShortcutsPane(viewModel: viewModel)
                    case .general: GeneralPane(viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(section)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.18), value: section)
    }
}

private struct PaneHeader: View {
    let section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(section.index)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.accentColor)
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 28, height: 1)
                Text(section.title.uppercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(2.8)
                    .foregroundStyle(Palette.muted)
            }

            Text(section.title)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(.white)

            Text(section.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtle)
        }
    }
}

private struct Card<Content: View>: View {
    var title: String? = nil
    var caption: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(Palette.muted)
                    if let caption {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 4)
                        Text(caption)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Palette.dim)
                    }
                }
            }
            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.cardStroke, lineWidth: 1)
        )
    }
}

private struct ToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool

    init(title: String, description: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white)
                if let description {
                    Text(description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

private struct AppsPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        let filtered = viewModel.filtered
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "FILTER", caption: "\(filtered.count) of \(viewModel.apps.count)") {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    TextField("Type to filter applications", text: $viewModel.filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                    if !viewModel.filter.isEmpty {
                        Button {
                            viewModel.filter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.hairline, lineWidth: 1)
                )
            }

            Card(title: "SEARCHABLE") {
                if filtered.isEmpty {
                    EmptyState(icon: "magnifyingglass", text: "No matches.")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, item in
                            AppRow(
                                item: item,
                                isEnabled: viewModel.isEnabled(item),
                                onToggle: { viewModel.toggle(item) }
                            )
                            if idx < filtered.count - 1 {
                                Rectangle()
                                    .fill(Palette.hairline)
                                    .frame(height: 1)
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct AppRow: View {
    let item: AppItem
    let isEnabled: Bool
    let onToggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIconCache.shared.icon(forPath: item.path))
                .resizable()
                .frame(width: 22, height: 22)
            Text(item.name)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(isEnabled ? 0.95 : 0.45))
            Spacer()
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hover ? Color.white.opacity(0.03) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

private struct BookmarksPane: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var newName: String = ""
    @State private var newURL: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "BROWSER") {
                VStack(spacing: 12) {
                    ToggleRow(
                        title: "Include Zen bookmarks",
                        description: "Imports bookmarks from your Zen browser profile and merges them with the list below. Open with ⇧⌘Space.",
                        isOn: Binding(
                            get: { viewModel.includeZenBookmarks },
                            set: { viewModel.setIncludeZenBookmarks($0) }
                        )
                    )
                    ToggleRow(
                        title: "Include Firefox bookmarks",
                        description: "Imports bookmarks from your Firefox profile (~/Library/Application Support/Firefox/Profiles/). Picks the most recently used profile.",
                        isOn: Binding(
                            get: { viewModel.includeFirefoxBookmarks },
                            set: { viewModel.setIncludeFirefoxBookmarks($0) }
                        )
                    )
                }
            }

            Card(title: "CUSTOM", caption: "\(viewModel.managedBookmarks.count) saved") {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        BookmarkField(placeholder: "Name", text: $newName, width: 130)
                        BookmarkField(placeholder: "https://example.com", text: $newURL, width: nil, onSubmit: addBookmark)
                        Button(action: addBookmark) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Add")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(addDisabled ? Color.white.opacity(0.06) : Color.accentColor)
                            )
                            .opacity(addDisabled ? 0.55 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(addDisabled)
                    }

                    if viewModel.managedBookmarks.isEmpty {
                        EmptyState(icon: "bookmark", text: "No custom bookmarks yet. Add one above.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.managedBookmarks.enumerated()), id: \.element.id) { idx, bookmark in
                                SettingsBookmarkRow(bookmark: bookmark) {
                                    viewModel.removeBookmark(id: bookmark.id)
                                }
                                if idx < viewModel.managedBookmarks.count - 1 {
                                    Rectangle()
                                        .fill(Palette.hairline)
                                        .frame(height: 1)
                                        .padding(.leading, 34)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var addDisabled: Bool {
        newName.trimmingCharacters(in: .whitespaces).isEmpty ||
        newURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addBookmark() {
        viewModel.addBookmark(name: newName, url: newURL)
        newName = ""
        newURL = ""
    }
}

private struct BookmarkField: View {
    let placeholder: String
    @Binding var text: String
    let width: CGFloat?
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.25))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
            .frame(maxWidth: width)
            .onSubmit { onSubmit?() }
    }
}

private struct SettingsBookmarkRow: View {
    let bookmark: Bookmark
    let onRemove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 22, height: 22)
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.subtle)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                Text(bookmark.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hover ? Color.red.opacity(0.95) : Palette.muted)
                    .padding(7)
                    .background(
                        Circle().fill(hover ? Color.red.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .help("Remove")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

private struct EmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Palette.dim)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
    }
}

private struct GeneralPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "STARTUP") {
                ToggleRow(
                    title: "Launch at login",
                    description: "Sift starts silently in the menu bar when you log in.",
                    isOn: Binding(
                        get: { viewModel.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    )
                )
            }

            Card(title: "SCREENSHOT", caption: viewModel.screenshotEnabled ? "ON" : "OFF") {
                VStack(alignment: .leading, spacing: 10) {
                    ToggleRow(
                        title: "Capture region tool",
                        description: "Adds a button next to the eye in the search field, and a \"Screenshot region\" command to the launcher. Draws a rectangle on the screen, opens a markup view to annotate, Enter copies it to clipboard.",
                        isOn: Binding(
                            get: { viewModel.screenshotEnabled },
                            set: { viewModel.setScreenshotEnabled($0) }
                        )
                    )
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .padding(.top, 1)
                        Text("First use will prompt for Screen Recording permission in System Settings.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Card(title: "SLEEP", caption: viewModel.sleepCommandsEnabled ? "ON" : "OFF") {
                VStack(alignment: .leading, spacing: 14) {
                    ToggleRow(
                        title: "Search sleep controls",
                        description: "Adds \"Disable sleep\" and \"Enable sleep\" to the launcher. When sleep is disabled, a yellow eye appears at the right of the search bar — click it to toggle back.",
                        isOn: Binding(
                            get: { viewModel.sleepCommandsEnabled },
                            set: { viewModel.setSleepCommandsEnabled($0) }
                        )
                    )

                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)

                    SudoersStatusRow(viewModel: viewModel)
                }
                .onAppear { viewModel.refreshSudoersStatus() }
            }

            Card(title: "BACKDROP") {
                VStack(alignment: .leading, spacing: 14) {
                    ToggleRow(
                        title: "Blur and dim the desktop",
                        description: "Adds a frosted, slightly darkened overlay across the rest of the screen while Sift is visible.",
                        isOn: Binding(
                            get: { viewModel.backdropEnabled },
                            set: { viewModel.setBackdropEnabled($0) }
                        )
                    )

                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)

                    IntensityRow(viewModel: viewModel)
                        .opacity(viewModel.backdropEnabled ? 1 : 0.45)
                        .disabled(!viewModel.backdropEnabled)

                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)

                    PsychedelicToggleRow(viewModel: viewModel)
                        .opacity(viewModel.backdropEnabled ? 1 : 0.45)
                        .disabled(!viewModel.backdropEnabled)

                    PsychedelicIntensityRow(viewModel: viewModel)
                        .opacity(viewModel.backdropEnabled && viewModel.psychedelicEnabled ? 1 : 0.45)
                        .disabled(!viewModel.backdropEnabled || !viewModel.psychedelicEnabled)

                    PsychedelicEffectsRow(viewModel: viewModel)
                        .opacity(viewModel.backdropEnabled && viewModel.psychedelicEnabled ? 1 : 0.45)
                        .disabled(!viewModel.backdropEnabled || !viewModel.psychedelicEnabled)
                }
            }
        }
    }
}

private struct PsychedelicToggleRow: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PsychedelicPreviewChip()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Psychedelic mode")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.white)
                    Text("RANDOM")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(red: 1, green: 0.4, blue: 0.7), Color(red: 0.5, green: 0.9, blue: 1)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        )
                }
                Text("Each time Sift opens, a different trip plays across the backdrop — waves, plasma, aurora, starfield, matrix, tunnel, spirograph, lightning, CRT, vortex, confetti, grid floor, phyllotaxis, pixel sort, fireflies, sunburst, EKG, bouncing balls, sonar, or hex cells.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { viewModel.psychedelicEnabled },
                set: { viewModel.setPsychedelicEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
    }
}

private struct PsychedelicIntensityRow: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PSYCHEDELIC INTENSITY")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Palette.muted)
                Spacer()
                Text("\(Int(viewModel.psychedelicIntensity * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dim)
                Slider(
                    value: Binding(
                        get: { viewModel.psychedelicIntensity },
                        set: { viewModel.setPsychedelicIntensity($0) }
                    ),
                    in: 0...1
                )
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.subtle)
            }
        }
    }
}

private struct PsychedelicEffectsRow: View {
    @ObservedObject var viewModel: SettingsViewModel

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EFFECTS IN ROTATION")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Palette.muted)
                Spacer()
                Text("\(PsychedelicEffect.allCases.count - viewModel.disabledPsychedelicEffects.count)/\(PsychedelicEffect.allCases.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(PsychedelicEffect.allCases, id: \.key) { effect in
                    let enabled = !viewModel.disabledPsychedelicEffects.contains(effect.key)
                    Button {
                        viewModel.setPsychedelicEffectEnabled(effect.key, enabled: !enabled)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(enabled ? Color.accentColor : Palette.dim)
                            Text(effect.displayName)
                                .font(.system(size: 12))
                                .foregroundStyle(enabled ? .white : Palette.subtle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(enabled ? 0.05 : 0.02))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(enabled ? 0.08 : 0.04), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if viewModel.disabledPsychedelicEffects.count >= PsychedelicEffect.allCases.count {
                Text("All effects disabled — backdrop will skip the psychedelic layer.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.subtle)
            }
        }
    }
}

private struct PsychedelicPreviewChip: View {
    private static let lineCount = 7

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Color.black
                Canvas { gc, size in
                    for i in 0..<Self.lineCount {
                        var path = Path()
                        let baseY = (Double(i) + 0.5) / Double(Self.lineCount) * size.height
                        let phase = t * (0.6 + Double(i % 3) * 0.3) + Double(i) * 0.7
                        let amp = size.height * 0.08
                        let steps = 36
                        for s in 0...steps {
                            let u = Double(s) / Double(steps)
                            let x = size.width * u
                            let y = baseY + sin(u * 4 * .pi + phase) * amp + sin(u * 8 * .pi - phase * 0.6) * amp * 0.35
                            if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        let hue = ((Double(i) / Double(Self.lineCount)) + t * 0.1).truncatingRemainder(dividingBy: 1)
                        let color = Color(hue: hue, saturation: 0.9, brightness: 1.0)
                        gc.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    }
                }
                .blendMode(.plusLighter)
            }
            .saturation(1.3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct IntensityRow: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("INTENSITY")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Palette.muted)
                Spacer()
                Text("\(Int(viewModel.backdropIntensity * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            HStack(spacing: 10) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dim)
                Slider(
                    value: Binding(
                        get: { viewModel.backdropIntensity },
                        set: { viewModel.setBackdropIntensity($0) }
                    ),
                    in: 0...1
                )
                Image(systemName: "circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.subtle)
            }
        }
    }
}

private struct PositionPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var contextName: String? { viewModel.selectedScreenContext }
    private var contextPosition: PanelPosition { viewModel.panelPosition(forContext: contextName) }
    private var isOverridden: Bool {
        guard let name = contextName else { return false }
        return viewModel.perScreenPanelPositions[name] != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "SCREEN", caption: (contextName ?? "Default").uppercased()) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: Binding(
                        get: { viewModel.selectedScreenContext ?? "" },
                        set: { viewModel.selectedScreenContext = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Default (any screen)").tag("")
                        ForEach(viewModel.connectedScreenNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    if let name = contextName {
                        HStack(spacing: 8) {
                            Text(isOverridden ? "Custom anchor for this screen." : "Inheriting the Default anchor.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Palette.subtle)
                            Spacer()
                            if isOverridden {
                                Button("Reset to default") { viewModel.clearPanelPosition(forContext: name) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    } else {
                        Text("Fallback anchor used on any screen without its own override.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.subtle)
                    }
                }
            }

            Card(title: "ANCHOR", caption: positionLabel(contextPosition).uppercased()) {
                PositionPicker(
                    selection: Binding(
                        get: { viewModel.panelPosition(forContext: contextName) },
                        set: { viewModel.setPanelPosition(forContext: contextName, value: $0) }
                    )
                )
                .frame(maxWidth: .infinity)
            }

            Card(title: "HINT") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 1)
                    Text("Each connected display can have its own anchor. Default covers any screen you haven't customized yet — handy when you plug in something new.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { viewModel.refreshConnectedScreens() }
    }
}

private func positionLabel(_ position: PanelPosition) -> String {
    let rows = ["Top", "Top-mid", "Upper", "Middle", "Lower", "Bottom-mid", "Bottom"]
    let cols = ["left", "left-mid", "inner-left", "center", "inner-right", "right-mid", "right"]
    if position == .center { return "Center" }
    return "\(rows[position.row]) \(cols[position.column])"
}

private struct PositionPicker: View {
    @Binding var selection: PanelPosition

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let panelWidth = size.width * 0.40
            let panelHeight: CGFloat = 22

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 1)

                ScreenGuides()
                    .stroke(Color.white.opacity(0.05), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .padding(14)

                MenuBarMock()
                    .frame(height: 10)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 1)
                    .padding(.top, 1)
                    .frame(maxHeight: .infinity, alignment: .top)

                MiniSiftPanel(width: panelWidth, height: panelHeight)
                    .position(
                        panelCenter(for: selection, in: size, panelWidth: panelWidth, panelHeight: panelHeight)
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: selection)

                GridButtons(selection: $selection)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
    }

    private func panelCenter(for position: PanelPosition, in size: CGSize, panelWidth: CGFloat, panelHeight: CGFloat) -> CGPoint {
        let insetX: CGFloat = 16
        let topInset: CGFloat = 20
        let bottomInset: CGFloat = 16

        let leftX = insetX + panelWidth / 2
        let rightX = size.width - insetX - panelWidth / 2
        let xs = PanelPosition.interpolatedSteps(start: leftX, center: size.width / 2, end: rightX)

        let topY = topInset + panelHeight / 2
        let bottomY = size.height - bottomInset - panelHeight / 2
        let ys = PanelPosition.interpolatedSteps(start: topY, center: size.height / 2, end: bottomY)

        return CGPoint(x: xs[position.column], y: ys[position.row])
    }
}

private struct ScreenGuides: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let third = rect.width / 3
        p.move(to: CGPoint(x: rect.minX + third, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + third, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + third * 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + third * 2, y: rect.maxY))
        let thirdH = rect.height / 3
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + thirdH))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + thirdH))
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + thirdH * 2))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + thirdH * 2))
        return p
    }
}

private struct MenuBarMock: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.white.opacity(0.22)).frame(width: 4, height: 4)
            Circle().fill(Color.white.opacity(0.22)).frame(width: 4, height: 4)
            Spacer()
            Circle().fill(Color.white.opacity(0.22)).frame(width: 4, height: 4)
            Circle().fill(Color.white.opacity(0.22)).frame(width: 4, height: 4)
            Circle().fill(Color.white.opacity(0.22)).frame(width: 4, height: 4)
        }
        .padding(.horizontal, 8)
    }
}

private struct MiniSiftPanel: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.95), lineWidth: 1.5)
            )
            .overlay(
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 4)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
            )
            .frame(width: width, height: height)
            .shadow(color: Color.accentColor.opacity(0.45), radius: 8, x: 0, y: 2)
    }
}

private struct GridButtons: View {
    @Binding var selection: PanelPosition

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<PanelPosition.gridSize, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<PanelPosition.gridSize, id: \.self) { col in
                        let position = PanelPosition(row: row, column: col)
                        GridDot(position: position, selected: selection == position) {
                            selection = position
                        }
                    }
                }
            }
        }
        .padding(10)
    }
}

private struct DevicesPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EmptyView()
                .onAppear { viewModel.refreshPairedDevices() }
            Card(title: "STATUS STRIP", caption: viewModel.statusStripEnabled ? "ON" : "OFF") {
                VStack(spacing: 14) {
                    ToggleRow(
                        title: "Show \"now playing\" strip",
                        description: "When the search field is empty and audio is actively playing, a strip under it shows the output that's producing sound right now. Hides automatically when nothing is playing. Display only.",
                        isOn: Binding(
                            get: { viewModel.statusStripEnabled },
                            set: { viewModel.setStatusStripEnabled($0) }
                        )
                    )
                }
            }

            Card(title: "SEARCH", caption: viewModel.devicesEnabled ? "ON" : "OFF") {
                VStack(spacing: 14) {
                    ToggleRow(
                        title: "Search devices in the launcher",
                        description: "When you start typing in ⌘Space, paired Bluetooth devices match alongside apps. Enter on a device connects or disconnects it.",
                        isOn: Binding(
                            get: { viewModel.devicesEnabled },
                            set: { viewModel.setDevicesEnabled($0) }
                        )
                    )

                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)

                    ToggleRow(
                        title: "Include audio outputs in search",
                        description: "Also lists output devices (built-in speakers, displays with audio, AirPlay). Enter swaps the active output.",
                        isOn: Binding(
                            get: { viewModel.audioSwitcherEnabled },
                            set: { viewModel.setAudioSwitcherEnabled($0) }
                        )
                    )
                    .opacity(viewModel.devicesEnabled ? 1 : 0.5)
                    .disabled(!viewModel.devicesEnabled)
                }
            }

            Card(title: "BLUETOOTH", caption: "\(viewModel.pairedDevices.count) paired") {
                HStack {
                    Spacer()
                    Button {
                        viewModel.refreshPairedDevices()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Refresh")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Palette.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.pairedDevices.isEmpty {
                    EmptyState(icon: "wave.3.right", text: "No paired Bluetooth devices found.")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.pairedDevices.enumerated()), id: \.element.id) { idx, device in
                            DevicePickerRow(viewModel: viewModel, device: device)
                            if idx < viewModel.pairedDevices.count - 1 {
                                Rectangle()
                                    .fill(Palette.hairline)
                                    .frame(height: 1)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            }
            .opacity((viewModel.devicesEnabled || viewModel.statusStripEnabled) ? 1 : 0.55)
            .disabled(!viewModel.devicesEnabled && !viewModel.statusStripEnabled)

            Card(title: "NOTE") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 1)
                    Text("Pair devices in System Settings → Bluetooth first. Sift only connects to devices already known to macOS — it doesn't pair new ones. Connection takes 1–3 seconds.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct DevicePickerRow: View {
    @ObservedObject var viewModel: SettingsViewModel
    let device: DeviceItem
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(device.isActive ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.06))
                    .frame(width: 32, height: 32)
                Image(systemName: device.category.systemImageName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(device.isActive ? Color.accentColor : .white.opacity(0.75))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(viewModel.isDeviceEnabled(device) ? 0.95 : 0.5))
                Text(device.isActive ? "Connected" : "Not connected")
                    .font(.system(size: 10.5))
                    .foregroundStyle(device.isActive ? Color.accentColor.opacity(0.9) : Palette.muted)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.isDeviceEnabled(device) },
                set: { _ in viewModel.toggleDevice(device) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hover ? Color.white.opacity(0.03) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

private struct SudoersStatusRow: View {
    @ObservedObject var viewModel: SettingsViewModel

    private static let manualCommand = #"echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1" | sudo tee /etc/sudoers.d/sift > /dev/null && sudo chmod 0440 /etc/sudoers.d/sift"#

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: viewModel.sudoersConfigured
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(viewModel.sudoersConfigured
                        ? Color(red: 0.4, green: 0.85, blue: 0.55)
                        : Color(red: 1.0, green: 0.78, blue: 0.25))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Sudoers rule")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Text(viewModel.sudoersConfigured
                        ? "/etc/sudoers.d/sift is installed — toggling works without a password prompt."
                        : "Not installed. Sift can't toggle sleep until the rule is created.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    viewModel.refreshSudoersStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Palette.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Re-check status")
            }

            if !viewModel.sudoersConfigured {
                VStack(alignment: .leading, spacing: 10) {
                    CopyableCommand(
                        label: "FROM SOURCE",
                        command: "just sudoers"
                    )
                    CopyableCommand(
                        label: "ONE-LINER (NO SOURCE)",
                        command: Self.manualCommand
                    )
                }
            }
        }
    }
}

private struct CopyableCommand: View {
    let label: String
    let command: String
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Palette.muted)

            HStack(alignment: .top, spacing: 10) {
                Text(command)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    justCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        justCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(justCopied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(justCopied
                        ? Color(red: 0.4, green: 0.85, blue: 0.55)
                        : .white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.18), value: justCopied)
        }
    }
}

private struct GridDot: View {
    let position: PanelPosition
    let selected: Bool
    let onSelect: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                Color.clear
                Circle()
                    .fill(selected ? Color.accentColor : (hover ? Color.white.opacity(0.55) : Color.white.opacity(0.22)))
                    .frame(width: selected ? 7 : (hover ? 5 : 3),
                           height: selected ? 7 : (hover ? 5 : 3))
                    .shadow(color: selected ? Color.accentColor.opacity(0.6) : .clear, radius: 4)
                    .animation(.easeOut(duration: 0.14), value: selected)
                    .animation(.easeOut(duration: 0.12), value: hover)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(positionLabel(position))
    }
}

private struct ShortcutsPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "MODE", caption: viewModel.combinedSearch ? "COMBINED" : "SEPARATE") {
                ToggleRow(
                    title: "One shortcut for everything",
                    description: "Mix bookmarks into the launcher's search results. The dedicated bookmarks shortcut is disabled while this is on.",
                    isOn: Binding(
                        get: { viewModel.combinedSearch },
                        set: { viewModel.setCombinedSearch($0) }
                    )
                )
            }

            Card(title: "GLOBAL", caption: "Press a combination with at least one modifier") {
                VStack(spacing: 14) {
                    ShortcutRow(
                        label: "Open launcher",
                        sublabel: "Toggles the app search panel.",
                        binding: Binding(
                            get: { viewModel.launcherHotkey },
                            set: { viewModel.setLauncherHotkey($0) }
                        )
                    )

                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)

                    ShortcutRow(
                        label: "Open bookmarks",
                        sublabel: viewModel.combinedSearch
                            ? "Disabled — combined mode mixes bookmarks into the launcher."
                            : "Toggles the bookmark search panel.",
                        binding: Binding(
                            get: { viewModel.bookmarksHotkey },
                            set: { viewModel.setBookmarksHotkey($0) }
                        )
                    )
                    .opacity(viewModel.combinedSearch ? 0.45 : 1)
                    .disabled(viewModel.combinedSearch)
                }
            }

            HStack {
                Spacer()
                Button {
                    viewModel.resetHotkeys()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Reset to defaults")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Card(title: "NOTE") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.orange.opacity(0.8))
                        .padding(.top, 1)
                    Text("If a combination is already claimed by macOS (like ⌘Space for Spotlight) the registration will silently fail. Free the shortcut in System Settings → Keyboard, or choose another combination here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ShortcutRow: View {
    let label: String
    let sublabel: String
    @Binding var binding: Hotkey

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white)
                Text(sublabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.subtle)
            }
            Spacer(minLength: 12)
            KeyRecorder(hotkey: $binding)
        }
    }
}

private struct KeyRecorder: View {
    @Binding var hotkey: Hotkey
    @State private var recording = false

    var body: some View {
        ZStack {
            KeyCaptureRepresentable(isRecording: $recording, hotkey: $hotkey)
                .frame(width: 0, height: 0)
                .opacity(0)

            Button(action: { recording.toggle() }) {
                HStack(spacing: 8) {
                    if recording {
                        PulsingDot()
                        Text("Press a key…")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text(hotkey.displayString())
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .tracking(0.5)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 138)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(recording ? Color.accentColor.opacity(0.14) : Color.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(recording ? Color.accentColor.opacity(0.85) : Palette.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PulsingDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.4)
            .shadow(color: Color.accentColor.opacity(0.8), radius: on ? 4 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

private struct KeyCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotkey: Hotkey

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCapture = { code, mods in
            self.hotkey = Hotkey(keyCode: code, modifiers: mods)
            self.isRecording = false
        }
        view.onCancel = {
            self.isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else {
            if nsView.window?.firstResponder === nsView {
                DispatchQueue.main.async {
                    nsView.window?.makeFirstResponder(nil)
                }
            }
        }
    }
}

private final class KeyCaptureView: NSView {
    var onCapture: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let mods = carbonModifiers(from: event.modifierFlags)
        if event.keyCode == 53 && mods == 0 {
            onCancel?()
            return
        }
        guard mods != 0 else {
            NSSound.beep()
            return
        }
        onCapture?(UInt32(event.keyCode), mods)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        keyDown(with: event)
        return true
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= Hotkey.cmdMask }
        if flags.contains(.shift) { mods |= Hotkey.shiftMask }
        if flags.contains(.option) { mods |= Hotkey.optionMask }
        if flags.contains(.control) { mods |= Hotkey.controlMask }
        return mods
    }
}
