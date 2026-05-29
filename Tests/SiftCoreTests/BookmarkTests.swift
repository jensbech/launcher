import Foundation
import Testing
@testable import SiftCore

struct BookmarkTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("bookmarks.json")
    }

    @Test func bookmarkStore_roundTripsManagedBookmarks() {
        let url = tempURL()
        let store = BookmarkStore(fileURL: url)
        let bookmarks = [
            Bookmark(id: "a", name: "Hacker News", url: "https://news.ycombinator.com", source: .managed),
            Bookmark(id: "b", name: "GitHub", url: "https://github.com", source: .managed)
        ]
        store.save(bookmarks)

        let reloaded = BookmarkStore(fileURL: url).load()
        #expect(reloaded.count == 2)
        #expect(reloaded.contains(where: { $0.id == "a" && $0.name == "Hacker News" }))
        #expect(reloaded.allSatisfy { $0.source == .managed })
    }

    @Test func bookmarkStore_dropsImportedEntriesOnSave() {
        let url = tempURL()
        let store = BookmarkStore(fileURL: url)
        store.save([
            Bookmark(name: "Local", url: "https://example.com", source: .managed),
            Bookmark(name: "Imported", url: "https://other.com", source: .zen)
        ])
        let reloaded = BookmarkStore(fileURL: url).load()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.source == .managed)
    }

    @Test func bookmarkIndex_dedupesByURL_managedWins() {
        let managed = [Bookmark(id: "m", name: "Custom Title", url: "https://example.com", source: .managed)]
        let imported = [Bookmark(id: "i", name: "Imported Title", url: "https://example.com/", source: .zen)]
        let merged = BookmarkIndex.merged(managed: managed, imported: imported)
        #expect(merged.count == 1)
        #expect(merged.first?.name == "Custom Title")
    }

    @Test func bookmarkIndex_keepsDistinctURLs() {
        let merged = BookmarkIndex.merged(
            managed: [Bookmark(name: "A", url: "https://a.com")],
            imported: [Bookmark(name: "B", url: "https://b.com", source: .zen)]
        )
        #expect(merged.count == 2)
    }

    @Test func config_defaults_includeZenBookmarksTrue() {
        let config = Config()
        #expect(config.includeZenBookmarks == true)
    }

    @Test func fuzzyMatcher_genericSearch_filtersBookmarks() {
        let bookmarks = [
            Bookmark(name: "Hacker News", url: "https://news.ycombinator.com"),
            Bookmark(name: "GitHub", url: "https://github.com"),
            Bookmark(name: "Hacker Noon", url: "https://hackernoon.com")
        ]
        let results = FuzzyMatcher.search("hac", in: bookmarks, name: { $0.name })
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.0.name.lowercased().contains("hac") })
    }
}
