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
        let highlightedName: AttributedString
        let displayName: String
        let displayURL: String

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

        var isEnvGroup: Bool {
            if case .envGroup = kind { return true }
            return false
        }
    }

    struct ActionsState: Equatable {
        let source: Bookmark
        let actions: [BookmarkAction]
        var selectedIndex: Int
        var subActions: SubActionsState?
    }

    struct SubActionsState: Equatable {
        let parentAction: BookmarkAction
        let expansion: ActionExpansion
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
    private let usageStore: UsageStore
    private var usage: UsageStats
    private var allBookmarks: [Bookmark] = []
    private var bookmarkNameChars: [String: [Character]] = [:]
    private var bookmarkUrlChars: [String: [Character]] = [:]
    private var lastZenMTime: Date?
    private var hasLoadedZen = false
    private var lastFirefoxMTime: Date?
    private var hasLoadedFirefox = false
    private var refreshing = false

    init(store: Store, bookmarkStore: BookmarkStore = BookmarkStore(), usageStore: UsageStore = UsageStore()) {
        self.store = store
        self.bookmarkStore = bookmarkStore
        self.usageStore = usageStore
        self.usage = usageStore.load()
        refreshIndex()
    }

    func recordBookmarkOpen(_ bookmark: Bookmark) {
        usage.record(bookmark.id)
        usageStore.save(usage)
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
        if value == query && actionsState == nil { return }
        if actionsState != nil { actionsState = nil }
        guard value != query else { return }
        query = value
        runSearch()
    }

    func enterActions() {
        if var state = actionsState {
            guard state.subActions == nil,
                  state.actions.indices.contains(state.selectedIndex),
                  let expansion = state.actions[state.selectedIndex].expansion else { return }
            state.subActions = SubActionsState(
                parentAction: state.actions[state.selectedIndex],
                expansion: expansion,
                selectedIndex: 0
            )
            actionsState = state
            GitHubActionCache.shared.ensure(expansion.cacheKey)
            return
        }
        guard results.indices.contains(selectedIndex) else { return }
        let result = results[selectedIndex]
        let actions = Self.actions(for: result)
        guard !actions.isEmpty else { return }
        actionsState = ActionsState(source: result.primaryBookmark, actions: actions, selectedIndex: 0, subActions: nil)
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
                    url: variant.bookmark.url,
                    recordID: variant.bookmark.id
                )
            }
        }
    }

    static func hasActions(for result: Result) -> Bool {
        switch result.kind {
        case .single(let b):
            return BookmarkActions.hasActions(for: b)
        case .envGroup(_, let variants, _):
            return !variants.isEmpty
        }
    }

    @discardableResult
    func tryExitActions() -> Bool {
        if var state = actionsState, state.subActions != nil {
            state.subActions = nil
            actionsState = state
            return true
        }
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
        let snapshot = usage
        let nameChars = self.bookmarkNameChars
        let urlChars = self.bookmarkUrlChars
        let now = Date()
        let matches = FuzzyMatcher.searchPrecomputed(
            query,
            in: allBookmarks,
            nameChars: { nameChars[$0.id] ?? FuzzyMatcher.lowercasedChars($0.name) },
            secondaryChars: { urlChars[$0.id] ?? FuzzyMatcher.lowercasedChars($0.url) },
            name: { $0.name },
            boost: { snapshot.boost(for: $0.id, now: now) }
        )
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
                output.append(Result(
                    kind: .single(bookmark),
                    match: match,
                    highlightedName: BookmarkRow.highlight(displayName: bookmark.name, matchedIndices: match.matched),
                    displayName: bookmark.name,
                    displayURL: bookmark.url
                ))
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
                let displayName = BookmarkEnv.strippedTitle(defaultBookmark.name)
                output.append(Result(
                    kind: .envGroup(defaultBookmark: defaultBookmark, variants: ordered, templateURL: key),
                    match: entry.bestMatch,
                    highlightedName: BookmarkRow.highlight(displayName: displayName, matchedIndices: entry.bestMatch.matched),
                    displayName: displayName,
                    displayURL: key
                ))
            } else {
                let bookmark = entry.variants[0].bookmark
                output.append(Result(
                    kind: .single(bookmark),
                    match: entry.bestMatch,
                    highlightedName: BookmarkRow.highlight(displayName: bookmark.name, matchedIndices: entry.bestMatch.matched),
                    displayName: bookmark.name,
                    displayURL: bookmark.url
                ))
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
            if var sub = state.subActions {
                let count = subActionItemCount(for: sub)
                guard count > 0 else { return }
                sub.selectedIndex = min(sub.selectedIndex + 1, count - 1)
                state.subActions = sub
                actionsState = state
                return
            }
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
            if var sub = state.subActions {
                let count = subActionItemCount(for: sub)
                guard count > 0 else { return }
                sub.selectedIndex = max(sub.selectedIndex - 1, 0)
                state.subActions = sub
                actionsState = state
                return
            }
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
            if let sub = state.subActions {
                guard case .loaded(let items) = GitHubActionCache.shared.snapshot(sub.expansion.cacheKey) ?? .loading,
                      items.indices.contains(sub.selectedIndex) else { return }
                recordBookmarkOpen(state.source)
                onOpenURL?(items[sub.selectedIndex].url)
                return
            }
            guard state.actions.indices.contains(state.selectedIndex) else { return }
            let action = state.actions[state.selectedIndex]
            if let recordID = action.recordID {
                usage.record(recordID)
                usageStore.save(usage)
            } else {
                recordBookmarkOpen(state.source)
            }
            onOpenURL?(action.url)
            return
        }
        guard results.indices.contains(selectedIndex) else { return }
        let bookmark = results[selectedIndex].primaryBookmark
        recordBookmarkOpen(bookmark)
        onOpen?(bookmark)
    }

    private func subActionItemCount(for sub: SubActionsState) -> Int {
        if case .loaded(let items) = GitHubActionCache.shared.snapshot(sub.expansion.cacheKey) ?? .loading {
            return items.count
        }
        return 0
    }

    func escape() {
        if tryExitActions() { return }
        onEscape?()
    }

    @discardableResult
    func copySelectedURL() -> Bool {
        if let state = actionsState {
            if let sub = state.subActions,
               case .loaded(let items) = GitHubActionCache.shared.snapshot(sub.expansion.cacheKey) ?? .loading,
               items.indices.contains(sub.selectedIndex) {
                let item = items[sub.selectedIndex]
                copy(url: item.url, flashID: "sub:\(item.id)")
                return true
            }
            if state.actions.indices.contains(state.selectedIndex) {
                let action = state.actions[state.selectedIndex]
                copy(url: action.url, flashID: "action:\(action.id)")
                return true
            }
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
        let config = store.load()
        let includeZen = config.includeZenBookmarks
        let includeFirefox = config.includeFirefoxBookmarks
        let managed = bookmarkStore.load()
        let cachedZen = allBookmarks.filter { $0.source == .zen }
        let cachedFirefox = allBookmarks.filter { $0.source == .firefox }
        let currentZenMTime = includeZen ? ZenBookmarkImporter.modificationTime() : nil
        let currentFirefoxMTime = includeFirefox ? FirefoxBookmarkImporter.modificationTime() : nil
        let needsZenReload = includeZen && (!hasLoadedZen || currentZenMTime != lastZenMTime)
        let needsFirefoxReload = includeFirefox && (!hasLoadedFirefox || currentFirefoxMTime != lastFirefoxMTime)

        let imported = (includeZen ? cachedZen : []) + (includeFirefox ? cachedFirefox : [])
        allBookmarks = BookmarkIndex.merged(managed: managed, imported: imported)
        rebuildBookmarkCharCache()
        FaviconCache.shared.prefetch(bookmarks: allBookmarks)
        if !query.isEmpty { runSearch() }

        if !includeZen {
            hasLoadedZen = false
            lastZenMTime = nil
        }
        if !includeFirefox {
            hasLoadedFirefox = false
            lastFirefoxMTime = nil
        }

        guard (needsZenReload || needsFirefoxReload), !refreshing else { return }
        refreshing = true

        Task.detached(priority: .userInitiated) { [weak self] in
            let zenMtime = includeZen ? ZenBookmarkImporter.modificationTime() : nil
            let zen = includeZen ? ZenBookmarkImporter.load() : []
            let firefoxMtime = includeFirefox ? FirefoxBookmarkImporter.modificationTime() : nil
            let firefox = includeFirefox ? FirefoxBookmarkImporter.load() : []
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.allBookmarks = BookmarkIndex.merged(managed: managed, imported: zen + firefox)
                self.rebuildBookmarkCharCache()
                FaviconCache.shared.prefetch(bookmarks: self.allBookmarks)
                if includeZen {
                    self.lastZenMTime = zenMtime
                    self.hasLoadedZen = true
                }
                if includeFirefox {
                    self.lastFirefoxMTime = firefoxMtime
                    self.hasLoadedFirefox = true
                }
                self.refreshing = false
                if !self.query.isEmpty { self.runSearch() }
            }
        }
    }

    private func rebuildBookmarkCharCache() {
        var nameChars: [String: [Character]] = [:]
        var urlChars: [String: [Character]] = [:]
        nameChars.reserveCapacity(allBookmarks.count)
        urlChars.reserveCapacity(allBookmarks.count)
        for bookmark in allBookmarks {
            nameChars[bookmark.id] = FuzzyMatcher.lowercasedChars(bookmark.name)
            urlChars[bookmark.id] = FuzzyMatcher.lowercasedChars(bookmark.url)
        }
        bookmarkNameChars = nameChars
        bookmarkUrlChars = urlChars
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
                            ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                                BookmarkRow(
                                    displayURL: result.displayURL,
                                    source: result.primaryBookmark.source,
                                    highlightedName: result.highlightedName,
                                    selected: index == viewModel.selectedIndex,
                                    icon: faviconCache.icon(for: result.primaryBookmark.url),
                                    missed: result.match.missed,
                                    hasActions: BookmarkViewModel.hasActions(for: result),
                                    copyFlashing: viewModel.copyFlashID == "result:\(result.id)"
                                )
                                .id(result.id)
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
                        if viewModel.results.indices.contains(newIndex) {
                            proxy.scrollTo(viewModel.results[newIndex].id)
                        }
                    }
                }
            }
        }
        .frame(width: 560)
        .background(
            ZStack {
                VisualEffectBackground()
                Color.veil(0.62)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct BookmarkRow: View {
    let displayURL: String
    let source: Bookmark.Source
    let highlightedName: AttributedString
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
                        .fill(fallbackTint(for: source))
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

    static func highlight(displayName: String, matchedIndices: [Int]) -> AttributedString {
        let chars = Array(displayName)
        let matched = Set(matchedIndices)
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

private func fallbackTint(for source: Bookmark.Source) -> Color {
    switch source {
    case .zen: return Color.orange.opacity(0.25)
    case .firefox: return Color(red: 0.95, green: 0.45, blue: 0.18).opacity(0.28)
    case .managed: return Color.accentColor.opacity(0.28)
    }
}

struct BookmarkActionsList: View {
    let state: BookmarkViewModel.ActionsState
    let viewModel: BookmarkViewModel

    var body: some View {
        if let sub = state.subActions {
            SubActionsList(
                parentTitle: sub.parentAction.title,
                bookmarkName: state.source.name,
                expansion: sub.expansion,
                selectedIndex: sub.selectedIndex,
                copyFlashID: viewModel.copyFlashID,
                onSelect: { index in
                    guard var current = viewModel.actionsState, var s = current.subActions else { return }
                    s.selectedIndex = index
                    current.subActions = s
                    viewModel.actionsState = current
                },
                onActivate: { viewModel.activateSelection() }
            )
        } else {
            actionList
        }
    }

    private var actionList: some View {
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
                Text(hintText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(state.actions.enumerated()), id: \.element.id) { index, action in
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
                                    if action.expansion != nil {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(index == state.selectedIndex ? .primary : .secondary)
                                            .padding(.leading, 2)
                                    }
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(index == state.selectedIndex ? Color.accentColor.opacity(0.35) : Color.clear)
                            .id(action.id)
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
                    if state.actions.indices.contains(newIndex) {
                        proxy.scrollTo(state.actions[newIndex].id)
                    }
                }
            }
        }
    }

    private var hintText: String {
        let selected = state.actions.indices.contains(state.selectedIndex) ? state.actions[state.selectedIndex] : nil
        if selected?.expansion != nil {
            return "→ to expand · ← to go back"
        }
        return "← to go back"
    }
}
