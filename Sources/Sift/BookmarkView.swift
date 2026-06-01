import SwiftUI
import AppKit
import SiftCore

@MainActor
final class BookmarkViewModel: ObservableObject {
    static let resultLimit = 100

    struct Result: Identifiable {
        enum Kind {
            case single(Bookmark)
            case envGroup(defaultBookmark: Bookmark, variants: [(env: String, bookmark: Bookmark)], templateURL: String)
        }
        let kind: Kind
        let match: FuzzyMatch

        var id: String {
            switch kind {
            case .single(let b): return b.id
            case .envGroup(_, _, let template): return "env:\(template)"
            }
        }

        var primaryBookmark: Bookmark {
            switch kind {
            case .single(let b): return b
            case .envGroup(let b, _, _): return b
            }
        }

        var displayName: String {
            switch kind {
            case .single(let b): return b.name
            case .envGroup(let b, _, _): return BookmarkEnv.strippedTitle(b.name)
            }
        }

        var displayURL: String {
            switch kind {
            case .single(let b): return b.url
            case .envGroup(_, _, let template): return template
            }
        }

        var isEnvGroup: Bool {
            if case .envGroup = kind { return true }
            return false
        }
    }

    struct ActionsState: Equatable {
        let source: Bookmark
        let actions: [BookmarkAction]
        var selectedIndex: Int
    }

    @Published var query: String = ""
    @Published var results: [Result] = []
    @Published var selectedIndex: Int = 0
    @Published var focusToken: Int = 0
    @Published var actionsState: ActionsState? = nil
    @Published var copyFlashID: String? = nil

    private var copyFlashTask: Task<Void, Never>? = nil

    var onOpen: ((Bookmark) -> Void)?
    var onOpenURL: ((String) -> Void)?
    var onEscape: (() -> Void)?

    var isInActionsMode: Bool { actionsState != nil }

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
        actionsState = nil
        focusToken &+= 1
        refreshIndex()
    }

    func updateQuery(_ value: String) {
        DebugLog.write("BookmarkVM.updateQuery in='\(value)' prevQuery='\(query)'")
        if actionsState != nil { actionsState = nil }
        query = value
        runSearch()
    }

    func enterActions() {
        guard actionsState == nil,
              results.indices.contains(selectedIndex) else { return }
        let result = results[selectedIndex]
        let actions = Self.actions(for: result)
        guard !actions.isEmpty else { return }
        actionsState = ActionsState(source: result.primaryBookmark, actions: actions, selectedIndex: 0)
    }

    static func actions(for result: Result) -> [BookmarkAction] {
        switch result.kind {
        case .single(let b):
            return BookmarkActions.actions(for: b)
        case .envGroup(_, let variants, _):
            return variants.map { variant in
                BookmarkAction(
                    id: "env-\(variant.env)",
                    title: variant.env.capitalized,
                    symbol: BookmarkEnv.symbol(forEnv: variant.env),
                    url: variant.bookmark.url
                )
            }
        }
    }

    @discardableResult
    func tryExitActions() -> Bool {
        guard actionsState != nil else { return false }
        actionsState = nil
        return true
    }

    func runSearch() {
        DebugLog.write("BookmarkVM.runSearch query='\(query)' allBookmarks=\(allBookmarks.count)")
        guard !query.isEmpty else {
            results = []
            return
        }
        let matches = FuzzyMatcher.search(query, in: allBookmarks, name: { $0.name }, secondary: { $0.url })
        results = Self.groupedResults(matches, limit: Self.resultLimit)
        DebugLog.write("BookmarkVM.runSearch matched=\(matches.count) results=\(results.count)")
        selectedIndex = 0
    }

    private static func groupedResults(_ matches: [(Bookmark, FuzzyMatch)], limit: Int) -> [Result] {
        struct GroupAccum {
            var variants: [(env: String, bookmark: Bookmark)] = []
            var bestMatch: FuzzyMatch
        }

        var groupOrder: [String] = []
        var groups: [String: GroupAccum] = [:]
        var output: [Result] = []

        for (bookmark, match) in matches {
            if let info = BookmarkEnv.info(forURL: bookmark.url) {
                let key = info.normalized
                if groups[key] == nil {
                    groups[key] = GroupAccum(bestMatch: match)
                    groupOrder.append(key)
                }
                var entry = groups[key]!
                if !entry.variants.contains(where: { $0.env == info.env }) {
                    entry.variants.append((info.env, bookmark))
                }
                if match.score > entry.bestMatch.score || match.missed < entry.bestMatch.missed {
                    entry.bestMatch = match
                }
                groups[key] = entry
            } else {
                output.append(Result(kind: .single(bookmark), match: match))
            }
        }

        for key in groupOrder {
            guard let entry = groups[key] else { continue }
            if entry.variants.count >= 2 {
                let ordered = BookmarkEnv.preferenceOrder.compactMap { env in
                    entry.variants.first { $0.env == env }
                } + entry.variants.filter { v in
                    !BookmarkEnv.preferenceOrder.contains(v.env)
                }
                let defaultBookmark = ordered.first?.bookmark ?? entry.variants[0].bookmark
                output.append(Result(
                    kind: .envGroup(defaultBookmark: defaultBookmark, variants: ordered, templateURL: key),
                    match: entry.bestMatch
                ))
            } else {
                output.append(Result(kind: .single(entry.variants[0].bookmark), match: entry.bestMatch))
            }
        }

        output.sort { a, b in
            if a.match.missed != b.match.missed { return a.match.missed < b.match.missed }
            if a.match.score != b.match.score { return a.match.score > b.match.score }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }

        return Array(output.prefix(limit))
    }

    func moveDown() {
        if var state = actionsState {
            guard !state.actions.isEmpty else { return }
            state.selectedIndex = min(state.selectedIndex + 1, state.actions.count - 1)
            actionsState = state
            return
        }
        guard !results.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, results.count - 1)
    }

    func moveUp() {
        if var state = actionsState {
            guard !state.actions.isEmpty else { return }
            state.selectedIndex = max(state.selectedIndex - 1, 0)
            actionsState = state
            return
        }
        guard !results.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func activateSelection() {
        if let state = actionsState {
            guard state.actions.indices.contains(state.selectedIndex) else { return }
            onOpenURL?(state.actions[state.selectedIndex].url)
            return
        }
        guard results.indices.contains(selectedIndex) else { return }
        onOpen?(results[selectedIndex].primaryBookmark)
    }

    func escape() {
        if tryExitActions() { return }
        onEscape?()
    }

    @discardableResult
    func copySelectedURL() -> Bool {
        if let state = actionsState, state.actions.indices.contains(state.selectedIndex) {
            let action = state.actions[state.selectedIndex]
            copy(url: action.url, flashID: "action:\(action.id)")
            return true
        }
        guard results.indices.contains(selectedIndex) else { return false }
        copy(url: results[selectedIndex].primaryBookmark.url, flashID: "result:\(results[selectedIndex].id)")
        return true
    }

    private func copy(url: String, flashID: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url, forType: .string)
        copyFlashID = flashID
        copyFlashTask?.cancel()
        copyFlashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            if self?.copyFlashID == flashID { self?.copyFlashID = nil }
        }
    }

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
                    onCancel: { viewModel.escape() },
                    onMoveRight: { viewModel.enterActions() },
                    onMoveLeft: { viewModel.tryExitActions() }
                )
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            if let state = viewModel.actionsState {
                Divider()
                BookmarkActionsList(state: state, viewModel: viewModel)
            } else if !viewModel.results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<viewModel.results.count, id: \.self) { index in
                                let result = viewModel.results[index]
                                BookmarkRow(
                                    displayName: result.displayName,
                                    displayURL: result.displayURL,
                                    source: result.primaryBookmark.source,
                                    query: viewModel.query,
                                    selected: index == viewModel.selectedIndex,
                                    icon: faviconCache.icon(for: result.primaryBookmark.url),
                                    missed: result.match.missed,
                                    hasActions: !BookmarkViewModel.actions(for: result).isEmpty,
                                    copyFlashing: viewModel.copyFlashID == "result:\(result.id)"
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectedIndex = index
                                    viewModel.activateSelection()
                                }
                                .onAppear { faviconCache.requestIcon(for: result.primaryBookmark.url) }
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

struct BookmarkRow: View {
    let displayName: String
    let displayURL: String
    let source: Bookmark.Source
    let query: String
    let selected: Bool
    let icon: NSImage?
    let missed: Int
    let hasActions: Bool
    var copyFlashing: Bool = false

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
                        .fill(source == .zen ? Color.orange.opacity(0.25) : Color.accentColor.opacity(0.28))
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(highlightedName)
                Text(displayURL)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if copyFlashing {
                CopiedBadge()
            } else {
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
                if hasActions {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor.opacity(0.35) : Color.clear)
        .opacity(isApproximate ? 0.55 : 1.0)
    }

    private var highlightedName: AttributedString {
        let chars = Array(displayName)
        let matched = Set(FuzzyMatcher.matchedIndices(query: query, candidate: displayName) ?? [])
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

struct BookmarkActionsList: View {
    let state: BookmarkViewModel.ActionsState
    let viewModel: BookmarkViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(state.source.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("← to go back")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<state.actions.count, id: \.self) { index in
                            let action = state.actions[index]
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.primary.opacity(0.10))
                                    Image(systemName: action.symbol)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.primary.opacity(0.9))
                                }
                                .frame(width: 32, height: 32)
                                Text(action.title)
                                    .font(.system(size: 15))
                                Spacer()
                                if viewModel.copyFlashID == "action:\(action.id)" {
                                    CopiedBadge()
                                } else {
                                    Text(action.url.replacingOccurrences(of: "https://", with: ""))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(index == state.selectedIndex ? Color.accentColor.opacity(0.35) : Color.clear)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                var s = state
                                s.selectedIndex = index
                                viewModel.actionsState = s
                                viewModel.activateSelection()
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
                .onChange(of: state.selectedIndex) { _, newIndex in
                    proxy.scrollTo(newIndex)
                }
            }
        }
    }
}
