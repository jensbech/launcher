import Foundation
import SiftCore

struct BookmarkAction: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let url: String
}

enum BookmarkActions {
    static func actions(for bookmark: Bookmark) -> [BookmarkAction] {
        guard let url = URL(string: bookmark.url),
              let host = url.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".github.com") else { return [] }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return [] }
        let owner = parts[0]
        let repo = parts[1]
        let base = "https://github.com/\(owner)/\(repo)"
        return [
            BookmarkAction(id: "actions",  title: "Actions",        symbol: "play.fill",                    url: "\(base)/actions"),
            BookmarkAction(id: "prs",      title: "Pull requests",  symbol: "arrow.triangle.pull",          url: "\(base)/pulls"),
            BookmarkAction(id: "issues",   title: "Issues",         symbol: "exclamationmark.circle",       url: "\(base)/issues"),
            BookmarkAction(id: "wiki",     title: "Wiki",           symbol: "book",                         url: "\(base)/wiki"),
            BookmarkAction(id: "releases", title: "Releases",       symbol: "tag",                          url: "\(base)/releases")
        ]
    }
}
