import SwiftUI
import AppKit
import Combine
import SiftCore

@MainActor
final class SiftViewModel: ObservableObject {
    struct BookmarkSearchResult: Identifiable {
        enum Kind {
            case single(Bookmark)
            case envGroup(defaultBookmark: Bookmark, variants: [(env: String, bookmark: Bookmark)], templateURL: String)
        }
        let kind: Kind
        let match: FuzzyMatch
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

    enum Result: Identifiable {
        case app(AppItem, FuzzyMatch)
        case device(DeviceItem, FuzzyMatch)
        case sleep(SleepCommand, FuzzyMatch)
        case bookmark(BookmarkSearchResult)
        case screenshot(FuzzyMatch)
        case systemInfo(SystemInfoCommand, FuzzyMatch)

        var id: String {
            switch self {
            case .app(let item, _): return "app:" + item.id
            case .device(let item, _): return item.id
            case .sleep(let cmd, _): return cmd.id
            case .bookmark(let r): return "bookmark:" + r.id
            case .screenshot: return "cmd:screenshot"
            case .systemInfo(let cmd, _): return cmd.id
            }
        }

        var missed: Int {
            switch self {
            case .app(_, let m): return m.missed
            case .device(_, let m): return m.missed
            case .sleep(_, let m): return m.missed
            case .bookmark(let r): return r.match.missed
            case .screenshot(let m): return m.missed
            case .systemInfo(_, let m): return m.missed
            }
        }

        var matchedInPrimary: Bool {
            switch self {
            case .app(_, let m): return !m.matched.isEmpty
            case .device(_, let m): return !m.matched.isEmpty
            case .sleep(_, let m): return !m.matched.isEmpty
            case .bookmark(let r): return !r.match.matched.isEmpty
            case .screenshot(let m): return !m.matched.isEmpty
            case .systemInfo(_, let m): return !m.matched.isEmpty
            }
        }

        var score: Int {
            switch self {
            case .app(_, let m): return m.score
            case .device(_, let m): return m.score
            case .sleep(_, let m): return m.score
            case .bookmark(let r): return r.match.score
            case .screenshot(let m): return m.score
            case .systemInfo(_, let m): return m.score
            }
        }

        var sortName: String {
            switch self {
            case .app(let a, _): return a.name
            case .device(let d, _): return d.name
            case .sleep(let s, _): return s.name
            case .bookmark(let r): return r.displayName
            case .screenshot: return "Screenshot region"
            case .systemInfo(let cmd, _): return cmd.name
            }
        }

        var typeRank: Int {
            switch self {
            case .sleep: return 4
            case .screenshot: return 4
            case .systemInfo: return 4
            case .app: return 3
            case .device: return 2
            case .bookmark: return 1
            }
        }

        var matchedIndices: [Int] {
            switch self {
            case .app(_, let m): return m.matched
            case .device(_, let m): return m.matched
            case .sleep(_, let m): return m.matched
            case .bookmark(let r): return r.match.matched
            case .screenshot(let m): return m.matched
            case .systemInfo(_, let m): return m.matched
            }
        }
    }

    private struct ScreenshotMatchTarget {
        let name = "Screenshot region"
    }

    struct RenderedResult: Identifiable {
        let result: Result
        let highlightedName: AttributedString

        var id: String { result.id }
    }

    @Published var query: String = ""
    @Published var results: [RenderedResult] = []
    @Published var selectedIndex: Int = 0
    @Published var focusToken: Int = 0
    @Published var statusDevices: [DeviceItem] = []
    @Published var visibleStatusDevices: [DeviceItem] = []
    @Published var devicesEnabled: Bool = false
    @Published var statusStripEnabled: Bool = false
    @Published var sleepCommandsEnabled: Bool = false
    @Published var sleepDisabled: Bool = false
    @Published var combinedSearch: Bool = false
    @Published var actionsState: ActionsState? = nil
    @Published var screenshotEnabled: Bool = false
    @Published var copyFlashID: String? = nil

    private var copyFlashTask: Task<Void, Never>? = nil
    private var pendingSearchTask: Task<Void, Never>? = nil
    private var runningOutputsCancellable: AnyCancellable?

    private static let searchDebounceNanos: UInt64 = 40_000_000

    var onLaunch: ((AppItem) -> Void)?
    var onEscape: (() -> Void)?
    var onDeviceActivated: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let store: Store
    private let usageStore: UsageStore
    private let bookmarkStore: BookmarkStore
    private var usage: UsageStats
    private var allApps: [AppItem] = []
    private var disabledIDs: Set<String> = []
    private var searchableApps: [AppItem] = []
    private var appNameChars: [String: [Character]] = [:]
    private var devices: [DeviceItem] = []
    private var disabledDeviceIDs: Set<String> = []
    private var audioSwitcherEnabled: Bool = true
    private var bookmarks: [Bookmark] = []
    private var bookmarkNameChars: [String: [Character]] = [:]
    private var bookmarkUrlChars: [String: [Character]] = [:]
    private var cachedZenBookmarks: [Bookmark] = []
    private var lastZenMTime: Date?
    private var cachedFirefoxBookmarks: [Bookmark] = []
    private var lastFirefoxMTime: Date?

    init(store: Store, usageStore: UsageStore = UsageStore(), bookmarkStore: BookmarkStore = BookmarkStore()) {
        self.store = store
        self.usageStore = usageStore
        self.bookmarkStore = bookmarkStore
        self.usage = usageStore.load()
        refreshIndex()
    }

    private func ensureRunningOutputsSubscription() {
        guard runningOutputsCancellable == nil else { return }
        runningOutputsCancellable = AudioMeterService.shared.$runningOutputDeviceIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeVisibleStatusDevices()
            }
    }

    private func cancelRunningOutputsSubscription() {
        runningOutputsCancellable?.cancel()
        runningOutputsCancellable = nil
    }

    private var lastIndexScanAt: Date?
    private static let indexScanThrottleSeconds: TimeInterval = 30

    func refreshIndex() {
        if let last = lastIndexScanAt,
           Date().timeIntervalSince(last) < Self.indexScanThrottleSeconds,
           !allApps.isEmpty {
            return
        }
        lastIndexScanAt = Date()
        Task.detached(priority: .utility) { [weak self] in
            let scanned = AppIndex.scan(directories: AppIndex.defaultSearchPaths)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.allApps = scanned
                self.rebuildSearchableApps()
                AppIconCache.shared.warm(paths: scanned.map { $0.path })
            }
        }
    }

    private func rebuildSearchableApps() {
        searchableApps = allApps.filter { !disabledIDs.contains($0.id) }
        var nameChars: [String: [Character]] = [:]
        nameChars.reserveCapacity(searchableApps.count)
        for item in searchableApps {
            nameChars[item.id] = FuzzyMatcher.lowercasedChars(item.name)
        }
        appNameChars = nameChars
    }

    func reload() {
        pendingSearchTask?.cancel()
        pendingSearchTask = nil
        query = ""
        results = []
        selectedIndex = 0
        let config = store.load()
        disabledIDs = config.disabledBundleIDs
        rebuildSearchableApps()
        disabledDeviceIDs = config.disabledDeviceIDs
        devicesEnabled = config.devicesEnabled
        statusStripEnabled = config.statusStripEnabled
        audioSwitcherEnabled = config.audioSwitcherEnabled
        sleepCommandsEnabled = config.sleepCommandsEnabled
        screenshotEnabled = config.screenshotEnabled
        combinedSearch = config.combinedSearch
        usage = usageStore.load()
        focusToken &+= 1
        refreshIndex()
        if devicesEnabled || statusStripEnabled {
            refreshDevices()
            ensureRunningOutputsSubscription()
        } else {
            devices = []
            statusDevices = []
            visibleStatusDevices = []
            cancelRunningOutputsSubscription()
        }
        if statusStripEnabled {
            NowPlayingService.shared.refresh()
        }
        if sleepCommandsEnabled {
            SleepService.shared.refresh()
            sleepDisabled = SleepService.shared.isDisabled
        } else {
            sleepDisabled = false
        }
        if combinedSearch {
            refreshBookmarks(config: config)
        } else {
            bookmarks = []
            bookmarkNameChars = [:]
            bookmarkUrlChars = [:]
        }
    }

    private func refreshBookmarks(config: Config) {
        let managed = bookmarkStore.load()
        let zen: [Bookmark]
        if config.includeZenBookmarks {
            let currentMTime = ZenBookmarkImporter.modificationTime()
            if let mtime = currentMTime, mtime == lastZenMTime, !cachedZenBookmarks.isEmpty {
                zen = cachedZenBookmarks
            } else {
                zen = ZenBookmarkImporter.load()
                cachedZenBookmarks = zen
                lastZenMTime = currentMTime
            }
        } else {
            zen = []
            cachedZenBookmarks = []
            lastZenMTime = nil
        }
        let firefox: [Bookmark]
        if config.includeFirefoxBookmarks {
            let currentMTime = FirefoxBookmarkImporter.modificationTime()
            if let mtime = currentMTime, mtime == lastFirefoxMTime, !cachedFirefoxBookmarks.isEmpty {
                firefox = cachedFirefoxBookmarks
            } else {
                firefox = FirefoxBookmarkImporter.load()
                cachedFirefoxBookmarks = firefox
                lastFirefoxMTime = currentMTime
            }
        } else {
            firefox = []
            cachedFirefoxBookmarks = []
            lastFirefoxMTime = nil
        }
        bookmarks = BookmarkIndex.merged(managed: managed, imported: zen + firefox)
        var nameChars: [String: [Character]] = [:]
        var urlChars: [String: [Character]] = [:]
        nameChars.reserveCapacity(bookmarks.count)
        urlChars.reserveCapacity(bookmarks.count)
        for bookmark in bookmarks {
            nameChars[bookmark.id] = FuzzyMatcher.lowercasedChars(bookmark.name)
            urlChars[bookmark.id] = FuzzyMatcher.lowercasedChars(bookmark.url)
        }
        bookmarkNameChars = nameChars
        bookmarkUrlChars = urlChars
        FaviconCache.shared.prefetch(bookmarks: bookmarks)
    }

    func refreshDevices() {
        let bt = BluetoothService.pairedDevices()
        let audio = AudioService.outputDevices()
        let combinedForSearch = bt + (audioSwitcherEnabled ? audio : [])
        devices = combinedForSearch.filter { !disabledDeviceIDs.contains($0.id) }
        statusDevices = (bt + audio).filter { $0.isActive && !disabledDeviceIDs.contains($0.id) }
        recomputeVisibleStatusDevices()
    }

    private func recomputeVisibleStatusDevices() {
        let runningIDs = AudioMeterService.shared.runningOutputDeviceIDs
        let playing = statusDevices.filter { device in
            device.kind == .audioOutput && runningIDs.contains(device.id)
        }
        let next: [DeviceItem] = playing
        if next != visibleStatusDevices { visibleStatusDevices = next }
    }

    func updateQuery(_ value: String) {
        DebugLog.write("SiftVM.updateQuery in='\(value)' prevQuery='\(query)'")
        if value == query && actionsState == nil { return }
        if actionsState != nil { actionsState = nil }
        guard value != query else { return }
        query = value

        pendingSearchTask?.cancel()
        pendingSearchTask = nil

        if value.isEmpty {
            results = []
            selectedIndex = 0
            return
        }

        pendingSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: SiftViewModel.searchDebounceNanos)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.query == value else { return }
            self.performSearch(for: value)
        }
    }

    private func performSearch(for value: String) {
        let appPool = searchableApps
        let appNameChars = self.appNameChars
        let now = Date()
        let appMatches = FuzzyMatcher.searchPrecomputed(
            value,
            in: appPool,
            nameChars: { appNameChars[$0.id] ?? FuzzyMatcher.lowercasedChars($0.name) },
            name: { $0.name },
            boost: { [usage] item in usage.boost(for: item.id, now: now) }
        )

        let deviceMatches: [(DeviceItem, FuzzyMatch)]
        if devicesEnabled {
            deviceMatches = FuzzyMatcher.search(value, in: devices, name: { $0.name })
        } else {
            deviceMatches = []
        }

        let sleepMatches: [(SleepCommand, FuzzyMatch)]
        if sleepCommandsEnabled {
            let commands = SleepCommand.available(isDisabled: sleepDisabled)
            sleepMatches = FuzzyMatcher.search(value, in: commands, name: { $0.name }, boost: { _ in 60 })
        } else {
            sleepMatches = []
        }

        let bookmarkResults: [BookmarkSearchResult]
        if combinedSearch {
            let snapshot = usage
            let nameChars = self.bookmarkNameChars
            let urlChars = self.bookmarkUrlChars
            let raw = FuzzyMatcher.searchPrecomputed(
                value,
                in: bookmarks,
                nameChars: { nameChars[$0.id] ?? FuzzyMatcher.lowercasedChars($0.name) },
                secondaryChars: { urlChars[$0.id] ?? FuzzyMatcher.lowercasedChars($0.url) },
                name: { $0.name },
                boost: { snapshot.boost(for: $0.id, now: now) }
            )
            bookmarkResults = Self.groupedBookmarkResults(raw)
        } else {
            bookmarkResults = []
        }

        let screenshotMatches: [FuzzyMatch]
        if screenshotEnabled {
            let target = ScreenshotMatchTarget()
            let raw = FuzzyMatcher.search(value, in: [target], name: { $0.name }, boost: { _ in 60 })
            screenshotMatches = raw.map { $0.1 }
        } else {
            screenshotMatches = []
        }

        let systemInfoMatches: [(SystemInfoCommand, FuzzyMatch)] = FuzzyMatcher.search(
            value,
            in: SystemInfoCommand.available(),
            name: { $0.name },
            boost: { _ in 60 }
        )

        var merged: [Result] = []
        merged.append(contentsOf: appMatches.map { Result.app($0.0, $0.1) })
        merged.append(contentsOf: bookmarkResults.map { Result.bookmark($0) })
        merged.append(contentsOf: deviceMatches.map { Result.device($0.0, $0.1) })
        merged.append(contentsOf: sleepMatches.map { Result.sleep($0.0, $0.1) })
        merged.append(contentsOf: screenshotMatches.map { Result.screenshot($0) })
        merged.append(contentsOf: systemInfoMatches.map { Result.systemInfo($0.0, $0.1) })

        merged.sort { a, b in
            if a.matchedInPrimary != b.matchedInPrimary {
                return a.matchedInPrimary && !b.matchedInPrimary
            }
            if a.typeRank != b.typeRank { return a.typeRank > b.typeRank }
            if a.missed != b.missed { return a.missed < b.missed }
            if a.score != b.score { return a.score > b.score }
            return a.sortName.localizedCaseInsensitiveCompare(b.sortName) == .orderedAscending
        }

        let queryLen = value.count
        let filtered: [Result]
        if queryLen <= 2 {
            filtered = merged.filter { $0.matchedInPrimary && $0.missed == 0 }
        } else {
            filtered = merged.filter { $0.matchedInPrimary }
        }
        let limit = queryLen <= 2 ? 12 : 30
        let sliced = Array(filtered.prefix(limit))
        results = sliced.map { result in
            RenderedResult(
                result: result,
                highlightedName: Self.highlight(rawName: Self.rawName(for: result), matched: result.matchedIndices)
            )
        }
        DebugLog.write("SiftVM.updateQuery matched=\(merged.count) results=\(results.count)")
        selectedIndex = 0
    }

    static func rawName(for result: Result) -> String {
        switch result {
        case .app(let item, _): return item.name
        case .device(let device, _): return device.name
        case .sleep(let cmd, _): return cmd.name
        case .bookmark(let bookmarkResult): return bookmarkResult.displayName
        case .screenshot: return "Screenshot region"
        case .systemInfo(let cmd, _): return cmd.name
        }
    }

    static func highlight(rawName: String, matched: [Int]) -> AttributedString {
        let matchedSet = Set(matched)
        let chars = Array(rawName)
        var result = AttributedString()
        for (index, char) in chars.enumerated() {
            var piece = AttributedString(String(char))
            if matchedSet.contains(index) {
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
        guard case .bookmark(let bookmarkResult) = results[selectedIndex].result else { return }
        let actions = Self.actions(for: bookmarkResult)
        guard !actions.isEmpty else { return }
        actionsState = ActionsState(
            source: bookmarkResult.primaryBookmark,
            actions: actions,
            selectedIndex: 0,
            subActions: nil
        )
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

    private func subActionItemCount(for sub: SubActionsState) -> Int {
        if case .loaded(let items) = GitHubActionCache.shared.snapshot(sub.expansion.cacheKey) ?? .loading {
            return items.count
        }
        return 0
    }

    private static func actions(for result: BookmarkSearchResult) -> [BookmarkAction] {
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

    private static func groupedBookmarkResults(_ matches: [(Bookmark, FuzzyMatch)]) -> [BookmarkSearchResult] {
        struct GroupAccum {
            var variants: [(env: String, bookmark: Bookmark)] = []
            var bestMatch: FuzzyMatch
        }

        var groupOrder: [String] = []
        var groups: [String: GroupAccum] = [:]
        var output: [BookmarkSearchResult] = []

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
                output.append(BookmarkSearchResult(
                    kind: .single(bookmark),
                    match: match,
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
                output.append(BookmarkSearchResult(
                    kind: .envGroup(defaultBookmark: defaultBookmark, variants: ordered, templateURL: key),
                    match: entry.bestMatch,
                    displayName: BookmarkEnv.strippedTitle(defaultBookmark.name),
                    displayURL: key
                ))
            } else {
                let bookmark = entry.variants[0].bookmark
                output.append(BookmarkSearchResult(
                    kind: .single(bookmark),
                    match: entry.bestMatch,
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

        return output
    }

    func activateSelection() {
        if let state = actionsState {
            if let sub = state.subActions {
                guard case .loaded(let items) = GitHubActionCache.shared.snapshot(sub.expansion.cacheKey) ?? .loading,
                      items.indices.contains(sub.selectedIndex) else { return }
                recordBookmarkUsage(state.source.id)
                openURL(items[sub.selectedIndex].url)
                onDeviceActivated?()
                return
            }
            guard state.actions.indices.contains(state.selectedIndex) else { return }
            let action = state.actions[state.selectedIndex]
            recordBookmarkUsage(action.recordID ?? state.source.id)
            openURL(action.url)
            onDeviceActivated?()
            return
        }
        guard results.indices.contains(selectedIndex) else { return }
        switch results[selectedIndex].result {
        case .app(let item, _):
            usage.record(item.id)
            usageStore.save(usage)
            onLaunch?(item)
        case .device(let item, _):
            activate(device: item)
            onDeviceActivated?()
        case .sleep(let cmd, _):
            cmd.perform()
            sleepDisabled = SleepService.shared.isDisabled
            onDeviceActivated?()
        case .bookmark(let bookmarkResult):
            recordBookmarkUsage(bookmarkResult.primaryBookmark.id)
            openURL(bookmarkResult.primaryBookmark.url)
            onDeviceActivated?()
        case .screenshot:
            onDeviceActivated?()
            DispatchQueue.main.async {
                ScreenshotController.shared.captureRegion()
            }
        case .systemInfo:
            break
        }
    }

    func startScreenshotCapture() {
        onDeviceActivated?()
        DispatchQueue.main.async {
            ScreenshotController.shared.captureRegion()
        }
    }

    func openSettings() {
        onOpenSettings?()
    }

    var onLogoTap: (() -> Void)?

    func tapLogo() {
        onLogoTap?()
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            NSWorkspace.shared.open(url)
        }
    }

    private func recordBookmarkUsage(_ id: String) {
        usage.record(id)
        usageStore.save(usage)
    }

    func toggleSleep() {
        guard sleepCommandsEnabled else { return }
        if sleepDisabled {
            SleepService.shared.enable()
        } else {
            SleepService.shared.disable()
        }
        sleepDisabled = SleepService.shared.isDisabled
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
        if case .bookmark(let bookmarkResult) = results[selectedIndex].result {
            copy(url: bookmarkResult.primaryBookmark.url, flashID: "result:\(bookmarkResult.id)")
            return true
        }
        return false
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
}

struct SiftView: View {
    @ObservedObject var viewModel: SiftViewModel
    @ObservedObject private var nowPlaying = NowPlayingService.shared

    private static let rowHeight: CGFloat = 48
    private static let maxRows: CGFloat = 7

    private var resultsHeight: CGFloat {
        let count = CGFloat(min(viewModel.results.count, Int(Self.maxRows)))
        return count * Self.rowHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                SiftLogoButton(onTap: { viewModel.tapLogo() })
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
                if viewModel.screenshotEnabled {
                    ScreenshotButton(onTrigger: { viewModel.startScreenshotCapture() })
                }
                if viewModel.sleepCommandsEnabled {
                    SleepEyeButton(
                        sleepDisabled: viewModel.sleepDisabled,
                        onToggle: { viewModel.toggleSleep() }
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            if let state = viewModel.actionsState {
                Divider()
                InlineActionsList(state: state, viewModel: viewModel)
            } else if !viewModel.results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, rendered in
                                ResultRow(
                                    result: rendered.result,
                                    highlightedName: rendered.highlightedName,
                                    selected: index == viewModel.selectedIndex,
                                    copyFlashing: viewModel.copyFlashID == "result:\(rendered.id)"
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectedIndex = index
                                    viewModel.activateSelection()
                                }
                            }
                        }
                    }
                    .frame(height: resultsHeight)
                    .onChange(of: viewModel.selectedIndex) { _, newIndex in
                        if viewModel.results.indices.contains(newIndex) {
                            proxy.scrollTo(viewModel.results[newIndex].id)
                        }
                    }
                }
            }

            if viewModel.statusStripEnabled && !viewModel.visibleStatusDevices.isEmpty {
                Divider().opacity(0.4)
                DeviceStatusStrip(
                    devices: viewModel.visibleStatusDevices,
                    nowPlaying: nowPlaying.info,
                    source: nowPlaying.source
                )
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

private struct DeviceStatusStrip: View {
    let devices: [DeviceItem]
    let nowPlaying: NowPlayingService.Info?
    let source: NowPlayingService.Source?

    var body: some View {
        HStack(spacing: 10) {
            AudioVisualizer()
            ForEach(devices) { device in
                HStack(spacing: 7) {
                    Image(systemName: device.category.systemImageName)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ink(0.88))
                    Text(device.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.ink(0.92))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.ink(0.06))
                )
            }
            SourcePillsRow(nowPlaying: nowPlaying, source: source)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct SourcePillsRow: View {
    let nowPlaying: NowPlayingService.Info?
    let source: NowPlayingService.Source?
    @State private var activeSources: [AudioMeterService.SourceApp] = []

    var body: some View {
        HStack(spacing: 10) {
            ForEach(activeSources) { src in
                SourcePill(source: src)
            }
            if let info = nowPlaying {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.ink(0.55))
                    Text(info.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.ink(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let artist = info.artist {
                        Text("·")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.ink(0.4))
                        Text(artist)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.ink(0.65))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            } else if let source, !activeSources.contains(where: { $0.id == source.bundleID }) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.ink(0.55))
                    Text(source.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.ink(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .onReceive(AudioMeterService.shared.$activeSources) { newSources in
            if newSources != activeSources { activeSources = newSources }
        }
    }
}

private struct SourcePill: View {
    let source: AudioMeterService.SourceApp

    var body: some View {
        HStack(spacing: 6) {
            if let icon = source.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ink(0.85))
            }
            Text(source.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.ink(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.ink(0.06))
        )
    }
}

private struct AudioVisualizer: View {
    @State private var bars: [Float] = Array(repeating: 0, count: AudioMeterService.barCount)
    @State private var isAvailable: Bool = false
    @State private var lastError: String?
    private let maxHeight: CGFloat = 13
    private static let bias: [CGFloat] = [0.65, 0.95, 1.0, 0.85, 0.55]
    private static let accent = Color(red: 0.36, green: 0.92, blue: 0.55)

    var body: some View {
        Group {
            if isAvailable {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<bars.count, id: \.self) { i in
                        let base = CGFloat(bars[i])
                        let b = Self.bias[i % Self.bias.count]
                        let h = max(2, min(maxHeight, base * b * maxHeight * 1.8))
                        Capsule()
                            .fill(Self.accent)
                            .frame(width: 2.2, height: h)
                            .animation(.easeOut(duration: 0.07), value: bars[i])
                    }
                }
            } else {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink(0.45))
                    .help(lastError ?? "Audio tap unavailable")
            }
        }
        .frame(height: maxHeight)
        .onReceive(AudioMeterService.shared.$bars) { newBars in
            if newBars != bars { bars = newBars }
        }
        .onReceive(AudioMeterService.shared.$isAvailable) { newValue in
            if newValue != isAvailable { isAvailable = newValue }
        }
        .onReceive(AudioMeterService.shared.$lastError) { newValue in
            if newValue != lastError { lastError = newValue }
        }
    }
}

struct ResultRow: View {
    let result: SiftViewModel.Result
    let highlightedName: AttributedString
    let selected: Bool
    var copyFlashing: Bool = false

    private var isApproximate: Bool { result.missed > 0 || !result.matchedInPrimary }

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
            Image(nsImage: AppIconCache.shared.icon(forPath: item.path))
                .resizable()
                .frame(width: 32, height: 32)
        case .device(let device, _):
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(device.isActive ? Color.accentColor.opacity(0.22) : Color.ink(0.07))
                    .frame(width: 32, height: 32)
                Image(systemName: device.category.systemImageName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(device.isActive ? Color.accentColor : Color.ink(0.75))
            }
        case .sleep(let cmd, _):
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.82, blue: 0.18).opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: cmd.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.18))
            }
        case .bookmark(let bookmarkResult):
            BookmarkLeadingIcon(url: bookmarkResult.primaryBookmark.url)
        case .screenshot:
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
                    .frame(width: 32, height: 32)
                Image(systemName: "selection.pin.in.out")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        case .systemInfo(let cmd, _):
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.ink(0.07))
                    .frame(width: 32, height: 32)
                Image(systemName: cmd.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ink(0.85))
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
                    .foregroundStyle(Color.ink(0.7))
            }
        case .sleep:
            Text("SYSTEM")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.18).opacity(0.85))
        case .bookmark(let bookmarkResult):
            if copyFlashing {
                CopiedBadge()
            } else {
                HStack(spacing: 6) {
                    Text(displayHost(for: bookmarkResult.displayURL))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if bookmarkResult.isEnvGroup {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
            }
        case .screenshot:
            Text("CAPTURE")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.accentColor.opacity(0.85))
        case .systemInfo(let cmd, _):
            if let value = cmd.trailingValue {
                Text(value)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ink(0.8))
                    .lineLimit(1)
            }
        }
    }

    private func displayHost(for url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return url }
        if host.hasPrefix("www.") { return String(host.dropFirst(4)) }
        return host
    }

}

private struct InlineActionsList: View {
    let state: SiftViewModel.ActionsState
    let viewModel: SiftViewModel

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

struct CopiedBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("COPIED")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
        }
        .foregroundStyle(Color(red: 0.36, green: 0.92, blue: 0.55))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color(red: 0.36, green: 0.92, blue: 0.55).opacity(0.14))
        )
        .transition(.opacity)
    }
}

private struct BookmarkLeadingIcon: View {
    let url: String
    @ObservedObject private var faviconCache = FaviconCache.shared

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.ink(0.07))
                .frame(width: 32, height: 32)
            if let icon = faviconCache.icon(for: url) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink(0.75))
            }
        }
        .onAppear { faviconCache.requestIcon(for: url) }
    }
}

private struct SiftLogoButton: View {
    let onTap: () -> Void
    @State private var hover = false
    @State private var press = false

    var body: some View {
        Button {
            press = true
            onTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { press = false }
        } label: {
            SiftMark(size: 20, color: Color.ink(hover ? 1 : 0.92))
                .scaleEffect(press ? 0.82 : (hover ? 1.1 : 1.0))
                .rotationEffect(.degrees(press ? 18 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hover = $0 }
        .help("✨")
        .animation(.spring(response: 0.18, dampingFraction: 0.55), value: press)
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

private struct ScreenshotButton: View {
    let onTrigger: () -> Void
    @State private var hover = false

    var body: some View {
        Button {
            onTrigger()
        } label: {
            Image(systemName: "selection.pin.in.out")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ink(hover ? 0.85 : 0.55))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hover ? Color.ink(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hover = $0 }
        .help("Capture a region (or type \"screenshot\")")
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

private struct SleepEyeButton: View {
    let sleepDisabled: Bool
    let onToggle: () -> Void
    @State private var hover = false

    private static let yellow = Color(red: 1.0, green: 0.82, blue: 0.18)

    var body: some View {
        Button {
            onToggle()
        } label: {
            Image(systemName: "eye.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(sleepDisabled
                    ? Self.yellow
                    : Color.ink(hover ? 0.55 : 0.32))
                .shadow(color: sleepDisabled
                    ? Self.yellow.opacity(0.5)
                    : .clear, radius: 3)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hover ? Color.ink(0.06) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hover = $0 }
        .help(sleepDisabled
            ? "Sleep is disabled — click to re-enable"
            : "Sleep is enabled — click to keep your Mac awake")
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.18), value: sleepDisabled)
    }
}

