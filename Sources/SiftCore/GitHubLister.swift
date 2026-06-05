import Foundation

public struct GitHubPR: Identifiable, Equatable, Sendable {
    public let number: Int
    public let title: String
    public let author: String
    public let headRefName: String
    public let isDraft: Bool
    public let url: String

    public init(number: Int, title: String, author: String, headRefName: String, isDraft: Bool, url: String) {
        self.number = number
        self.title = title
        self.author = author
        self.headRefName = headRefName
        self.isDraft = isDraft
        self.url = url
    }

    public var id: Int { number }
}

public struct GitHubBranch: Identifiable, Equatable, Sendable {
    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }

    public var id: String { name }
}

public struct GitHubRun: Identifiable, Equatable, Sendable {
    public let id: Int
    public let workflowName: String
    public let displayTitle: String
    public let headBranch: String
    public let status: String
    public let conclusion: String?
    public let url: String
    public let createdAt: String

    public init(id: Int, workflowName: String, displayTitle: String, headBranch: String, status: String, conclusion: String?, url: String, createdAt: String) {
        self.id = id
        self.workflowName = workflowName
        self.displayTitle = displayTitle
        self.headBranch = headBranch
        self.status = status
        self.conclusion = conclusion
        self.url = url
        self.createdAt = createdAt
    }
}

public enum GitHubListerError: Error, Equatable, Sendable {
    case ghNotFound
    case ghFailed(stderr: String, exitCode: Int32)
    case parseFailure
}

public enum GitHubLister {
    public static func prs(owner: String, repo: String) async -> Result<[GitHubPR], GitHubListerError> {
        let args = ["pr", "list",
                    "--repo", "\(owner)/\(repo)",
                    "--state", "open",
                    "--limit", "50",
                    "--json", "number,title,headRefName,isDraft,author,url"]
        return await runJSON(args) { data in
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            return arr.compactMap { obj -> GitHubPR? in
                guard let number = obj["number"] as? Int,
                      let title = obj["title"] as? String,
                      let headRefName = obj["headRefName"] as? String,
                      let isDraft = obj["isDraft"] as? Bool,
                      let url = obj["url"] as? String else { return nil }
                let author = (obj["author"] as? [String: Any])?["login"] as? String ?? ""
                return GitHubPR(number: number, title: title, author: author, headRefName: headRefName, isDraft: isDraft, url: url)
            }
        }
    }

    public static func branches(owner: String, repo: String) async -> Result<[GitHubBranch], GitHubListerError> {
        let args = ["api", "repos/\(owner)/\(repo)/branches?per_page=50"]
        return await runJSON(args) { data in
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            return arr.compactMap { obj -> GitHubBranch? in
                guard let name = obj["name"] as? String else { return nil }
                let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                return GitHubBranch(name: name, url: "https://github.com/\(owner)/\(repo)/tree/\(encoded)")
            }
        }
    }

    public static func runs(owner: String, repo: String) async -> Result<[GitHubRun], GitHubListerError> {
        let args = ["run", "list",
                    "--repo", "\(owner)/\(repo)",
                    "--limit", "10",
                    "--json", "databaseId,workflowName,displayTitle,headBranch,status,conclusion,url,createdAt"]
        return await runJSON(args) { data in
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            return arr.compactMap { obj -> GitHubRun? in
                guard let id = obj["databaseId"] as? Int,
                      let workflowName = obj["workflowName"] as? String,
                      let displayTitle = obj["displayTitle"] as? String,
                      let headBranch = obj["headBranch"] as? String,
                      let status = obj["status"] as? String,
                      let url = obj["url"] as? String,
                      let createdAt = obj["createdAt"] as? String else { return nil }
                let conclusion = obj["conclusion"] as? String
                return GitHubRun(id: id, workflowName: workflowName, displayTitle: displayTitle, headBranch: headBranch, status: status, conclusion: conclusion, url: url, createdAt: createdAt)
            }
        }
    }

    private static func runJSON<T: Sendable>(_ args: [String], decode: @Sendable @escaping (Data) -> T?) async -> Result<T, GitHubListerError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let gh = ghURL() else {
                    continuation.resume(returning: .failure(.ghNotFound))
                    return
                }
                let proc = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                proc.standardOutput = stdout
                proc.standardError = stderr
                proc.executableURL = gh
                proc.arguments = args
                proc.environment = ProcessInfo.processInfo.environment
                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: .failure(.ghNotFound))
                    return
                }
                proc.waitUntilExit()
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus != 0 {
                    let msg = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(returning: .failure(.ghFailed(stderr: msg.trimmingCharacters(in: .whitespacesAndNewlines), exitCode: proc.terminationStatus)))
                    return
                }
                guard let parsed = decode(data) else {
                    continuation.resume(returning: .failure(.parseFailure))
                    return
                }
                continuation.resume(returning: .success(parsed))
            }
        }
    }

    private static func ghURL() -> URL? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "command -v gh"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty, fm.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
