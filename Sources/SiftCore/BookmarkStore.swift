import Foundation

public final class BookmarkStore {
    public let fileURL: URL

    public init(fileURL: URL = BookmarkStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sift/bookmarks.json")
    }

    public func load() -> [Bookmark] {
        guard let data = try? Data(contentsOf: fileURL),
              let bookmarks = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            return []
        }
        return bookmarks.filter { $0.source == .managed }
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
    }
}
