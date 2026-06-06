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

    public func boost(for id: String, now: Date = Date()) -> Int {
        let count = launchCounts[id] ?? 0
        let countBoost: Int
        if count <= 0 {
            countBoost = 0
        } else {
            let scaled = log2(Double(count + 1)) * 14.0
            countBoost = min(90, Int(scaled.rounded()))
        }
        guard let last = lastLaunched[id] else { return countBoost }
        let hours = now.timeIntervalSince(last) / 3600
        let recencyBoost: Int
        switch hours {
        case ..<0.5: recencyBoost = 60
        case ..<2:   recencyBoost = 50
        case ..<8:   recencyBoost = 40
        case ..<24:  recencyBoost = 30
        case ..<72:  recencyBoost = 20
        case ..<168: recencyBoost = 12
        case ..<720: recencyBoost = 6
        default:     recencyBoost = 1
        }
        return countBoost + recencyBoost
    }

    public func boost(forAny ids: [String], now: Date = Date()) -> Int {
        ids.map { boost(for: $0, now: now) }.max() ?? 0
    }
}

public final class UsageStore {
    public let fileURL: URL
    private let lock = NSLock()
    private var cachedStats: UsageStats?
    private var cachedMtime: Date?

    public init(fileURL: URL = UsageStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sift/usage.json")
    }

    public func load() -> UsageStats {
        let currentMtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date

        lock.lock()
        if let cached = cachedStats, currentMtime == cachedMtime {
            defer { lock.unlock() }
            return cached
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: fileURL),
              let stats = try? JSONDecoder().decode(UsageStats.self, from: data) else {
            let fallback = UsageStats()
            lock.lock()
            cachedStats = fallback
            cachedMtime = currentMtime
            lock.unlock()
            return fallback
        }

        lock.lock()
        cachedStats = stats
        cachedMtime = currentMtime
        lock.unlock()
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
        let newMtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
        lock.lock()
        cachedStats = stats
        cachedMtime = newMtime
        lock.unlock()
    }
}
