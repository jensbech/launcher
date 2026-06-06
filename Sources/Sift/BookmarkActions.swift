import Foundation
import SiftCore

struct ActionExpansion: Equatable {
    let kind: GitHubActionCache.Kind
    let owner: String
    let repo: String

    var cacheKey: GitHubActionCache.Key {
        GitHubActionCache.Key(owner: owner, repo: repo, kind: kind)
    }
}

struct BookmarkAction: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let url: String
    let expansion: ActionExpansion?
    let recordID: String?

    init(id: String, title: String, symbol: String, url: String, expansion: ActionExpansion? = nil, recordID: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.url = url
        self.expansion = expansion
        self.recordID = recordID
    }
}

enum BookmarkEnv {
    static let preferenceOrder = ["dev", "test", "stage", "staging", "prod"]

    private static let patterns: [(needle: String, env: String)] = [
        ("-dev.", "dev"),
        ("-test.", "test"),
        ("-stage.", "stage"),
        ("-staging.", "staging"),
        ("-prod.", "prod"),
        (".dev.", "dev"),
        (".test.", "test"),
        (".stage.", "stage"),
        (".staging.", "staging"),
        (".prod.", "prod")
    ]

    static func info(forURL url: String) -> (env: String, normalized: String)? {
        for (needle, env) in patterns {
            guard url.range(of: needle) != nil else { continue }
            let prefix = String(needle.first!)
            let replacement = "\(prefix){env}."
            let normalized = url.replacingOccurrences(of: needle, with: replacement)
            return (env, normalized)
        }
        return nil
    }

    static func strippedTitle(_ title: String) -> String {
        var result = title
        for env in preferenceOrder {
            result = result.replacingOccurrences(of: " (\(env))", with: "")
        }
        return result
    }

    static func symbol(forEnv env: String) -> String {
        switch env {
        case "dev": return "hammer"
        case "test": return "flask"
        case "stage", "staging": return "theatermasks"
        case "prod": return "globe.americas"
        default: return "circle"
        }
    }
}

enum BookmarkActions {
    static func hasActions(for bookmark: Bookmark) -> Bool {
        guard let url = URL(string: bookmark.url),
              let host = url.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".github.com") else { return false }
        let parts = url.path.split(separator: "/")
        return parts.count >= 2
    }

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
            BookmarkAction(
                id: "actions", title: "Actions", symbol: "play.fill",
                url: "\(base)/actions",
                expansion: ActionExpansion(kind: .runs, owner: owner, repo: repo)
            ),
            BookmarkAction(
                id: "prs", title: "Pull requests", symbol: "arrow.triangle.pull",
                url: "\(base)/pulls",
                expansion: ActionExpansion(kind: .prs, owner: owner, repo: repo)
            ),
            BookmarkAction(
                id: "branches", title: "Branches", symbol: "arrow.triangle.branch",
                url: "\(base)/branches",
                expansion: ActionExpansion(kind: .branches, owner: owner, repo: repo)
            ),
            BookmarkAction(id: "issues",   title: "Issues",         symbol: "exclamationmark.circle",       url: "\(base)/issues"),
            BookmarkAction(id: "wiki",     title: "Wiki",           symbol: "book",                         url: "\(base)/wiki"),
            BookmarkAction(id: "releases", title: "Releases",       symbol: "tag",                          url: "\(base)/releases")
        ]
    }
}
