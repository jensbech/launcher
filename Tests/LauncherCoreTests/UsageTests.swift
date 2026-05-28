import Foundation
import Testing
@testable import LauncherCore

struct UsageTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("usage.json")
    }

    @Test func record_incrementsCountAndSetsDate() {
        var stats = UsageStats()
        let now = Date()
        stats.record("com.apple.Safari", at: now)
        stats.record("com.apple.Safari", at: now)
        #expect(stats.launchCounts["com.apple.Safari"] == 2)
        #expect(stats.lastLaunched["com.apple.Safari"] == now)
    }

    @Test func boost_isZeroForUnknownApp() {
        let stats = UsageStats()
        #expect(stats.boost(for: "com.unknown", now: Date()) == 0)
    }

    @Test func boost_increasesWithCount() {
        let now = Date()
        var few = UsageStats()
        few.launchCounts["a"] = 1
        few.lastLaunched["a"] = now
        var many = UsageStats()
        many.launchCounts["a"] = 9
        many.lastLaunched["a"] = now
        #expect(many.boost(for: "a", now: now) > few.boost(for: "a", now: now))
    }

    @Test func boost_recentBeatsStale() {
        let now = Date()
        var recent = UsageStats()
        recent.launchCounts["a"] = 3
        recent.lastLaunched["a"] = now
        var stale = UsageStats()
        stale.launchCounts["a"] = 3
        stale.lastLaunched["a"] = now.addingTimeInterval(-60 * 60 * 24 * 30)
        #expect(recent.boost(for: "a", now: now) > stale.boost(for: "a", now: now))
    }

    @Test func store_roundTrips() {
        let url = tempURL()
        var stats = UsageStats()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        stats.record("com.apple.Safari", at: now)
        UsageStore(fileURL: url).save(stats)

        let reloaded = UsageStore(fileURL: url).load()
        #expect(reloaded.launchCounts["com.apple.Safari"] == 1)
        #expect(reloaded.lastLaunched["com.apple.Safari"] == now)
    }

    @Test func store_missingFile_returnsEmpty() {
        let stats = UsageStore(fileURL: tempURL()).load()
        #expect(stats.launchCounts.isEmpty)
        #expect(stats.lastLaunched.isEmpty)
    }
}
