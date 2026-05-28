import SwiftUI
import AppKit
import LauncherCore

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [AppItem] = []
    @Published var selectedIndex: Int = 0
    @Published var focusToken: Int = 0

    var onLaunch: ((AppItem) -> Void)?
    var onEscape: (() -> Void)?

    private let store: Store
    private let usageStore: UsageStore
    private var usage: UsageStats
    private var allApps: [AppItem] = []
    private var disabledIDs: Set<String> = []

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
        disabledIDs = store.load().disabledBundleIDs
        usage = usageStore.load()
        focusToken &+= 1
        refreshIndex()
    }

    func updateQuery(_ value: String) {
        query = value
        let pool = allApps.filter { !disabledIDs.contains($0.id) }
        results = FuzzyMatcher.search(value, in: pool) { [usage] item in
            usage.boost(for: item.id)
        }
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
        let item = results[selectedIndex]
        usage.record(item.id)
        usageStore.save(usage)
        onLaunch?(item)
    }

    func escape() { onEscape?() }
}

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel

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

            if !viewModel.results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, item in
                                ResultRow(item: item, query: viewModel.query, selected: index == viewModel.selectedIndex)
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
                Color.black.opacity(0.40)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ResultRow: View {
    let item: AppItem
    let query: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 32, height: 32)
            Text(highlightedName)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.35) : Color.clear)
    }

    private var highlightedName: AttributedString {
        let chars = Array(item.name)
        let matched = Set(FuzzyMatcher.matchedIndices(query: query, candidate: item.name) ?? [])
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
