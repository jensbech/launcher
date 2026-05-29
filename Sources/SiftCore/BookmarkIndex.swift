import Foundation

public struct BookmarkIndex {
    public static func merged(managed: [Bookmark], imported: [Bookmark]) -> [Bookmark] {
        var seen = Set<String>()
        var result: [Bookmark] = []
        for entry in managed + imported {
            let key = normalizedURL(entry.url)
            if seen.insert(key).inserted {
                result.append(entry)
            }
        }
        return result
    }

    private static func normalizedURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
