import SwiftUI
import AppKit
import SiftCore

@MainActor
final class SiftViewModel: ObservableObject {
    enum Result: Identifiable {
        case app(AppItem, FuzzyMatch)
        case device(DeviceItem, FuzzyMatch)

        var id: String {
            switch self {
            case .app(let item, _): return "app:" + item.id
            case .device(let item, _): return item.id
            }
        }

        var missed: Int {
            switch self {
            case .app(_, let m): return m.missed
            case .device(_, let m): return m.missed
            }
        }
    }

    @Published var query: String = ""
    @Published var results: [Result] = []
    @Published var selectedIndex: Int = 0
    @Published var focusToken: Int = 0
    @Published var statusDevices: [DeviceItem] = []
    @Published var devicesEnabled: Bool = false
    @Published var statusStripEnabled: Bool = false

    var onLaunch: ((AppItem) -> Void)?
    var onEscape: (() -> Void)?
    var onDeviceActivated: (() -> Void)?

    private let store: Store
    private let usageStore: UsageStore
    private var usage: UsageStats
    private var allApps: [AppItem] = []
    private var disabledIDs: Set<String> = []
    private var devices: [DeviceItem] = []
    private var disabledDeviceIDs: Set<String> = []
    private var audioSwitcherEnabled: Bool = true

    init(store: Store, usageStore: UsageStore = UsageStore()) {
        self.store = store
        self.usageStore = usageStore
        self.usage = usageStore.load()
        refreshIndex()
    }

    func refreshIndex() {
        Task.detached(priority: .utility) {
            let scanned = AppIndex.scan(directories: AppIndex.defaultSearchPaths)
            await MainActor.run { self.allApps = scanned }
        }
    }

    func reload() {
        query = ""
        results = []
        selectedIndex = 0
        let config = store.load()
        disabledIDs = config.disabledBundleIDs
        disabledDeviceIDs = config.disabledDeviceIDs
        devicesEnabled = config.devicesEnabled
        statusStripEnabled = config.statusStripEnabled
        audioSwitcherEnabled = config.audioSwitcherEnabled
        usage = usageStore.load()
        focusToken &+= 1
        refreshIndex()
        if devicesEnabled || statusStripEnabled {
            refreshDevices()
        } else {
            devices = []
            statusDevices = []
        }
    }

    func refreshDevices() {
        let bt = BluetoothService.pairedDevices()
        let audio = audioSwitcherEnabled ? AudioService.outputDevices() : []
        devices = (bt + audio).filter { !disabledDeviceIDs.contains($0.id) }
        statusDevices = devices.filter { $0.isActive }
    }

    func updateQuery(_ value: String) {
        DebugLog.write("SiftVM.updateQuery in='\(value)' prevQuery='\(query)'")
        query = value

        let appPool = allApps.filter { !disabledIDs.contains($0.id) }
        let appMatches = FuzzyMatcher.search(value, in: appPool) { [usage] item in
            usage.boost(for: item.id)
        }

        let deviceMatches: [(DeviceItem, FuzzyMatch)]
        if devicesEnabled, !value.isEmpty {
            deviceMatches = FuzzyMatcher.search(value, in: devices, name: { $0.name })
        } else {
            deviceMatches = []
        }

        var merged: [Result] = []
        merged.append(contentsOf: appMatches.map { Result.app($0.0, $0.1) })
        merged.append(contentsOf: deviceMatches.map { Result.device($0.0, $0.1) })

        results = Array(merged.prefix(100))
        DebugLog.write("SiftVM.updateQuery matched=\(merged.count) results=\(results.count)")
        selectedIndex = 0
    }

    func moveDown() {
        guard !results.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, results.count - 1)
    }

    func moveUp() {
        guard !results.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func activateSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        switch results[selectedIndex] {
        case .app(let item, _):
            usage.record(item.id)
            usageStore.save(usage)
            onLaunch?(item)
        case .device(let item, _):
            activate(device: item)
            onDeviceActivated?()
        }
    }

    private func activate(device: DeviceItem) {
        switch device.kind {
        case .bluetooth:
            BluetoothService.toggle(deviceID: device.id) { [weak self] in
                Task { @MainActor in self?.refreshDevices() }
            }
        case .audioOutput:
            AudioService.setActive(deviceID: device.id)
        }
    }

    func escape() { onEscape?() }
}

struct SiftView: View {
    @ObservedObject var viewModel: SiftViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
                SearchField(
                    text: Binding(get: { viewModel.query }, set: { viewModel.updateQuery($0) }),
                    focusToken: viewModel.focusToken,
                    onMoveUp: { viewModel.moveUp() },
                    onMoveDown: { viewModel.moveDown() },
                    onSubmit: { viewModel.activateSelection() },
                    onCancel: { viewModel.escape() }
                )
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            if viewModel.statusStripEnabled && viewModel.query.isEmpty && !viewModel.statusDevices.isEmpty {
                Divider().opacity(0.4)
                DeviceStatusStrip(devices: viewModel.statusDevices)
            }

            if !viewModel.results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<viewModel.results.count, id: \.self) { index in
                                let result = viewModel.results[index]
                                ResultRow(
                                    result: result,
                                    query: viewModel.query,
                                    selected: index == viewModel.selectedIndex
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectedIndex = index
                                    viewModel.activateSelection()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: viewModel.selectedIndex) { _, newIndex in
                        proxy.scrollTo(newIndex)
                    }
                }
            }
        }
        .frame(width: 560)
        .background(
            ZStack {
                VisualEffectBackground()
                Color.black.opacity(0.62)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DeviceStatusStrip: View {
    let devices: [DeviceItem]

    var body: some View {
        HStack(spacing: 10) {
            Text("CONNECTED")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.4))
            ForEach(devices) { device in
                HStack(spacing: 6) {
                    Circle()
                        .fill(activeColor(for: device))
                        .frame(width: 6, height: 6)
                        .shadow(color: activeColor(for: device).opacity(0.7), radius: 3)
                    Image(systemName: device.category.systemImageName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(device.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func activeColor(for device: DeviceItem) -> Color {
        switch device.kind {
        case .audioOutput: return Color.accentColor
        case .bluetooth: return Color(red: 0.4, green: 0.85, blue: 0.55)
        }
    }
}

struct ResultRow: View {
    let result: SiftViewModel.Result
    let query: String
    let selected: Bool

    private var isApproximate: Bool { result.missed > 0 }

    var body: some View {
        HStack(spacing: 14) {
            leading
            title
            Spacer()
            trailing
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.35) : Color.clear)
        .opacity(isApproximate ? 0.55 : 1.0)
    }

    @ViewBuilder
    private var leading: some View {
        switch result {
        case .app(let item, _):
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 32, height: 32)
        case .device(let device, _):
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(device.isActive ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.07))
                    .frame(width: 32, height: 32)
                Image(systemName: device.category.systemImageName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(device.isActive ? Color.accentColor : .white.opacity(0.75))
            }
        }
    }

    private var title: some View {
        Text(highlightedName)
    }

    @ViewBuilder
    private var trailing: some View {
        switch result {
        case .app:
            if isApproximate {
                Text("~\(result.missed)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.12)))
            }
        case .device(let device, _):
            HStack(spacing: 6) {
                if device.isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.accentColor.opacity(0.7), radius: 3)
                }
                Text(device.actionLabel.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var rawName: String {
        switch result {
        case .app(let item, _): return item.name
        case .device(let device, _): return device.name
        }
    }

    private var highlightedName: AttributedString {
        let chars = Array(rawName)
        let matched = Set(FuzzyMatcher.matchedIndices(query: query, candidate: rawName) ?? [])
        var result = AttributedString()
        for (index, char) in chars.enumerated() {
            var piece = AttributedString(String(char))
            if matched.contains(index) {
                piece.font = .system(size: 16, weight: .semibold)
                piece.foregroundColor = .primary
            } else {
                piece.font = .system(size: 16, weight: .regular)
                piece.foregroundColor = .primary.opacity(0.85)
            }
            result += piece
        }
        return result
    }
}
