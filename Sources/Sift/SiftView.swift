import SwiftUI
import AppKit
import SiftCore

@MainActor
final class SiftViewModel: ObservableObject {
    struct Result: Identifiable {
        let item: AppItem
        let match: FuzzyMatch
        var id: String { item.id }
    }

    @Published var query: String = ""
    @Published var results: [Result] = []
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
        DebugLog.write("SiftVM.updateQuery in='\(value)' prevQuery='\(query)'")
        query = value
        let pool = allApps.filter { !disabledIDs.contains($0.id) }
        let matches = FuzzyMatcher.search(value, in: pool) { [usage] item in
            usage.boost(for: item.id)
        }
        results = matches.prefix(100).map { Result(item: $0.0, match: $0.1) }
        DebugLog.write("SiftVM.updateQuery matched=\(matches.count) results=\(results.count)")
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
        let item = results[selectedIndex].item
        usage.record(item.id)
        usageStore.save(usage)
        onLaunch?(item)
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

            if !viewModel.results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<viewModel.results.count, id: \.self) { index in
                                let result = viewModel.results[index]
                                ResultRow(
                                    item: result.item,
                                    query: viewModel.query,
                                    selected: index == viewModel.selectedIndex,
                                    missed: result.match.missed
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

struct ResultRow: View {
    let item: AppItem
    let query: String
    let selected: Bool
    let missed: Int

    private var isApproximate: Bool { missed > 0 }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 32, height: 32)
            Text(highlightedName)
            Spacer()
            if isApproximate {
                Text("~\(missed)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.12)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.35) : Color.clear)
        .opacity(isApproximate ? 0.55 : 1.0)
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
