import SwiftUI
import AppKit
import SiftCore

@MainActor
final class BookmarkViewModel: ObservableObject {
    static let resultLimit = 100

    struct Result: Identifiable {
        let bookmark: Bookmark
        let match: FuzzyMatch
        var id: String { bookmark.id }
    }

    @Published var query: String = ""
    @Published var results: [Result] = []
    @Published var selectedIndex: Int = 0
    @Published var focusToken: Int = 0

    var onOpen: ((Bookmark) -> Void)?
    var onEscape: (() -> Void)?

    private let store: Store
    private let bookmarkStore: BookmarkStore
    private var allBookmarks: [Bookmark] = []
    private var lastZenMTime: Date?
    private var hasLoadedZen = false
    private var refreshing = false

    init(store: Store, bookmarkStore: BookmarkStore = BookmarkStore()) {
        self.store = store
        self.bookmarkStore = bookmarkStore
        refreshIndex()
    }

    func reload() {
        query = ""
        results = []
        selectedIndex = 0
        focusToken &+= 1
        refreshIndex()
    }

    func updateQuery(_ value: String) {
        DebugLog.write("BookmarkVM.updateQuery in='\(value)' prevQuery='\(query)'")
        query = value
        runSearch()
    }

    func runSearch() {
        DebugLog.write("BookmarkVM.runSearch query='\(query)' allBookmarks=\(allBookmarks.count)")
        guard !query.isEmpty else {
            results = []
            return
        }
        let matches = FuzzyMatcher.search(query, in: allBookmarks, name: { $0.name }, secondary: { $0.url })
        results = matches.prefix(Self.resultLimit).map { Result(bookmark: $0.0, match: $0.1) }
        DebugLog.write("BookmarkVM.runSearch matched=\(matches.count) results=\(results.count)")
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
        onOpen?(results[selectedIndex].bookmark)
    }

    func escape() { onEscape?() }

    private func refreshIndex() {
        let includeZen = store.load().includeZenBookmarks
        let managed = bookmarkStore.load()
        let cachedZen = allBookmarks.filter { $0.source == .zen }
        let currentMTime = includeZen ? ZenBookmarkImporter.modificationTime() : nil
        let needsZenReload = includeZen && (!hasLoadedZen || currentMTime != lastZenMTime)

        allBookmarks = BookmarkIndex.merged(managed: managed, imported: includeZen ? cachedZen : [])
        FaviconCache.shared.prefetch(bookmarks: allBookmarks)
        if !query.isEmpty { runSearch() }

        if !includeZen {
            hasLoadedZen = false
            lastZenMTime = nil
            return
        }

        guard needsZenReload, !refreshing else { return }
        refreshing = true

        Task.detached(priority: .userInitiated) {
            let mtime = ZenBookmarkImporter.modificationTime()
            let zen = ZenBookmarkImporter.load()
            await MainActor.run {
                self.allBookmarks = BookmarkIndex.merged(managed: managed, imported: zen)
                FaviconCache.shared.prefetch(bookmarks: self.allBookmarks)
                self.lastZenMTime = mtime
                self.hasLoadedZen = true
                self.refreshing = false
                if !self.query.isEmpty { self.runSearch() }
            }
        }
    }
}

struct BookmarkView: View {
    @ObservedObject var viewModel: BookmarkViewModel
    @ObservedObject private var faviconCache = FaviconCache.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 18, weight: .regular))
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
                                BookmarkRow(
                                    item: result.bookmark,
                                    query: viewModel.query,
                                    selected: index == viewModel.selectedIndex,
                                    icon: faviconCache.icon(for: result.bookmark.url),
                                    missed: result.match.missed
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectedIndex = index
                                    viewModel.activateSelection()
                                }
                                .onAppear { faviconCache.requestIcon(for: result.bookmark.url) }
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

struct BookmarkRow: View {
    let item: Bookmark
    let query: String
    let selected: Bool
    let icon: NSImage?
    let missed: Int

    private var isApproximate: Bool { missed > 0 }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if let icon {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .padding(3)
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(item.source == .zen ? Color.orange.opacity(0.25) : Color.accentColor.opacity(0.28))
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(highlightedName)
                Text(item.url)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if isApproximate {
                Text("~\(missed)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
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
                piece.font = .system(size: 15, weight: .semibold)
                piece.foregroundColor = .primary
            } else {
                piece.font = .system(size: 15, weight: .regular)
                piece.foregroundColor = .primary.opacity(0.85)
            }
            result += piece
        }
        return result
    }
}
