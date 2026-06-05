import Foundation
import SiftCore

struct SubItem: Identifiable, Equatable {
    enum Tint: Equatable {
        case neutral
        case running
        case success
        case failure
        case warn
        case info
    }

    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let tint: Tint
    let url: String
}

@MainActor
final class GitHubActionCache: ObservableObject {
    static let shared = GitHubActionCache()

    enum Kind: String { case prs, branches, runs }

    struct Key: Hashable {
        let owner: String
        let repo: String
        let kind: Kind
    }

    enum Phase: Equatable {
        case loading
        case loaded(items: [SubItem])
        case failed(message: String)
    }

    @Published private(set) var entries: [Key: Phase] = [:]
    private var expiries: [Key: Date] = [:]
    private let ttl: TimeInterval = 30

    func snapshot(_ key: Key) -> Phase? { entries[key] }

    func ensure(_ key: Key) {
        if case .loading = entries[key] { return }
        if let exp = expiries[key], exp > Date(), entries[key] != nil { return }
        entries[key] = .loading
        Task { await fetch(key) }
    }

    func invalidate(_ key: Key) {
        entries.removeValue(forKey: key)
        expiries.removeValue(forKey: key)
    }

    private func fetch(_ key: Key) async {
        let phase: Phase
        switch key.kind {
        case .prs:
            phase = Self.phase(prs: await GitHubLister.prs(owner: key.owner, repo: key.repo))
        case .branches:
            phase = Self.phase(branches: await GitHubLister.branches(owner: key.owner, repo: key.repo))
        case .runs:
            phase = Self.phase(runs: await GitHubLister.runs(owner: key.owner, repo: key.repo))
        }
        entries[key] = phase
        expiries[key] = Date().addingTimeInterval(ttl)
    }

    private static func phase(prs: Result<[GitHubPR], GitHubListerError>) -> Phase {
        switch prs {
        case .failure(let err): return .failed(message: message(for: err))
        case .success(let items):
            let subs = items.map { pr in
                SubItem(
                    id: "pr-\(pr.number)",
                    title: "#\(pr.number) \(pr.title)",
                    subtitle: subtitleForPR(pr),
                    symbol: pr.isDraft ? "circle.dashed" : "arrow.triangle.pull",
                    tint: pr.isDraft ? .neutral : .info,
                    url: pr.url
                )
            }
            return .loaded(items: subs)
        }
    }

    private static func phase(branches: Result<[GitHubBranch], GitHubListerError>) -> Phase {
        switch branches {
        case .failure(let err): return .failed(message: message(for: err))
        case .success(let items):
            let subs = items.map { branch in
                SubItem(
                    id: "branch-\(branch.name)",
                    title: branch.name,
                    subtitle: nil,
                    symbol: "arrow.triangle.branch",
                    tint: .neutral,
                    url: branch.url
                )
            }
            return .loaded(items: subs)
        }
    }

    private static func phase(runs: Result<[GitHubRun], GitHubListerError>) -> Phase {
        switch runs {
        case .failure(let err): return .failed(message: message(for: err))
        case .success(let items):
            let subs = items.map { run -> SubItem in
                let (symbol, tint) = symbolAndTint(forRun: run)
                let subtitle = "\(run.workflowName) · \(run.headBranch)"
                return SubItem(
                    id: "run-\(run.id)",
                    title: run.displayTitle.isEmpty ? run.workflowName : run.displayTitle,
                    subtitle: subtitle,
                    symbol: symbol,
                    tint: tint,
                    url: run.url
                )
            }
            return .loaded(items: subs)
        }
    }

    private static func subtitleForPR(_ pr: GitHubPR) -> String {
        var parts: [String] = []
        if !pr.author.isEmpty { parts.append("@\(pr.author)") }
        parts.append(pr.headRefName)
        if pr.isDraft { parts.append("draft") }
        return parts.joined(separator: " · ")
    }

    private static func symbolAndTint(forRun run: GitHubRun) -> (String, SubItem.Tint) {
        switch run.status {
        case "queued", "waiting", "pending", "requested":
            return ("clock", .neutral)
        case "in_progress":
            return ("dot.radiowaves.left.and.right", .running)
        case "completed":
            switch run.conclusion ?? "" {
            case "success":
                return ("checkmark.circle.fill", .success)
            case "failure", "timed_out", "startup_failure":
                return ("xmark.octagon.fill", .failure)
            case "cancelled", "skipped", "stale":
                return ("minus.circle", .neutral)
            case "action_required":
                return ("exclamationmark.triangle.fill", .warn)
            case "neutral":
                return ("circle", .neutral)
            default:
                return ("questionmark.circle", .neutral)
            }
        default:
            return ("circle", .neutral)
        }
    }

    private static func message(for err: GitHubListerError) -> String {
        switch err {
        case .ghNotFound:
            return "gh CLI not found. Install via `brew install gh`."
        case .ghFailed(let stderr, _):
            if stderr.localizedCaseInsensitiveContains("authentication") || stderr.localizedCaseInsensitiveContains("not logged into") {
                return "gh not authenticated. Run `gh auth login`."
            }
            if stderr.isEmpty { return "gh command failed." }
            return stderr.split(separator: "\n").first.map(String.init) ?? "gh command failed."
        case .parseFailure:
            return "Could not parse gh output."
        }
    }
}
