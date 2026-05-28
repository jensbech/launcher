import Foundation

public struct UsageStats: Codable, Equatable {
    public var launchCounts: [String: Int]
    public var lastLaunched: [String: Date]

    public init(launchCounts: [String: Int] = [:], lastLaunched: [String: Date] = [:]) {
        self.launchCounts = launchCounts
        self.lastLaunched = lastLaunched
    }

    public mutating func record(_ bundleID: String, at date: Date = Date()) {
        launchCounts[bundleID, default: 0] += 1
        lastLaunched[bundleID] = date
    }

    public func boost(for bundleID: String, now: Date = Date()) -> Int {
        let countBoost = min(launchCounts[bundleID] ?? 0, 10) * 2
        guard let last = lastLaunched[bundleID] else { return countBoost }
        let hours = now.timeIntervalSince(last) / 3600
        let recencyBoost: Int
        switch hours {
        case ..<1: recencyBoost = 30
        case ..<24: recencyBoost = 20
        case ..<168: recencyBoost = 10
        default: recencyBoost = 3
        }
        return countBoost + recencyBoost
    }
}

public final class UsageStore {
    public let fileURL: URL

    public init(fileURL: URL = UsageStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Launcher/usage.json")
    }

    public func load() -> UsageStats {
        guard let data = try? Data(contentsOf: fileURL),
              let stats = try? JSONDecoder().decode(UsageStats.self, from: data) else {
            return UsageStats()
        }
        return stats
    }

    public func save(_ stats: UsageStats) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(stats) else { return }
        try? data.write(to: fileURL)
    }
}
