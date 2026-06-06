import Foundation

public final class BookmarkStore {
    public let fileURL: URL
    private let lock = NSLock()
    private var cachedBookmarks: [Bookmark]?
    private var cachedMtime: Date?

    public init(fileURL: URL = BookmarkStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sift/bookmarks.json")
    }

    public func load() -> [Bookmark] {
        let currentMtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date

        lock.lock()
        if let cached = cachedBookmarks, currentMtime == cachedMtime {
            defer { lock.unlock() }
            return cached
        }
        lock.unlock()

        let parsed: [Bookmark]
        if let data = try? Data(contentsOf: fileURL),
           let bookmarks = try? JSONDecoder().decode([Bookmark].self, from: data) {
            parsed = bookmarks.filter { $0.source == .managed }
        } else {
            parsed = []
        }

        lock.lock()
        cachedBookmarks = parsed
        cachedMtime = currentMtime
        lock.unlock()
        return parsed
    }

    public func save(_ bookmarks: [Bookmark]) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let managed = bookmarks.filter { $0.source == .managed }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(managed) else { return }
        try? data.write(to: fileURL)
        let newMtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
        lock.lock()
        cachedBookmarks = managed
        cachedMtime = newMtime
        lock.unlock()
    }
}
