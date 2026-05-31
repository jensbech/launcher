import Foundation
import CoreGraphics

public struct FuzzyMatch: Equatable, Sendable {
    public let score: Int
    public let matched: [Int]
    public let missed: Int

    public init(score: Int, matched: [Int], missed: Int) {
        self.score = score
        self.matched = matched
        self.missed = missed
    }

    public var isExact: Bool { missed == 0 }
}

public struct FuzzyMatcher {
    public static func match(query: String, candidate: String) -> FuzzyMatch? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return nil }

        let allowedMiss = allowedMissCount(forQueryLength: q.count)

        var qi = 0
        var ci = 0
        var indices: [Int] = []
        var score = 0
        var prevMatch = -2
        var missed = 0
        var currentRun = 0
        var longestRun = 0

        while qi < q.count {
            var found = false
            var scan = ci
            while scan < c.count {
                if c[scan] == q[qi] {
                    var bonus = 1
                    if scan == 0 {
                        bonus += 40
                    } else {
                        let prev = c[scan - 1]
                        if prev == " " || prev == "-" || prev == "_" || prev == "." {
                            bonus += 30
                        }
                    }
                    if prevMatch == scan - 1 {
                        bonus += 8
                        currentRun += 1
                    } else {
                        currentRun = 1
                    }
                    longestRun = max(longestRun, currentRun)
                    score += bonus
                    indices.append(scan)
                    prevMatch = scan
                    qi += 1
                    ci = scan + 1
                    found = true
                    break
                }
                scan += 1
            }
            if !found {
                missed += 1
                if missed > allowedMiss { return nil }
                qi += 1
                currentRun = 0
            }
        }

        if longestRun >= q.count - missed && longestRun >= 2 {
            score += 30
        }

        let penalty = missed * 50
        return FuzzyMatch(score: score - penalty, matched: indices, missed: missed)
    }

    public static func matchedIndices(query: String, candidate: String) -> [Int]? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var indices = Set<Int>()
        var anyMatched = false
        for token in tokens {
            if let m = match(query: token, candidate: candidate) {
                indices.formUnion(m.matched)
                anyMatched = true
            }
        }
        guard anyMatched else { return nil }
        return indices.sorted()
    }

    public static func score(query: String, candidate: String) -> Int? {
        match(query: query, candidate: candidate)?.score
    }

    public static func search(
        _ query: String,
        in items: [AppItem],
        boost: (AppItem) -> Int = { _ in 0 }
    ) -> [(AppItem, FuzzyMatch)] {
        search(query, in: items, name: { $0.name }, secondary: nil, boost: boost)
    }

    public static func search<Item>(
        _ query: String,
        in items: [Item],
        name: (Item) -> String,
        boost: (Item) -> Int = { _ in 0 }
    ) -> [(Item, FuzzyMatch)] {
        search(query, in: items, name: name, secondary: nil, boost: boost)
    }

    public static func search<Item>(
        _ query: String,
        in items: [Item],
        name: (Item) -> String,
        secondary: ((Item) -> String)?,
        boost: (Item) -> Int = { _ in 0 }
    ) -> [(Item, FuzzyMatch)] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        return items
            .compactMap { item -> (Item, FuzzyMatch)? in
                let primary = name(item)
                let secondaryText = secondary?(item) ?? ""

                var matchedInName = Set<Int>()
                var totalScore = 0
                var totalMissed = 0

                for token in tokens {
                    if let m = match(query: token, candidate: primary) {
                        totalScore += m.score
                        totalMissed += m.missed
                        matchedInName.formUnion(m.matched)
                    } else if !secondaryText.isEmpty,
                              let m = match(query: token, candidate: secondaryText) {
                        totalScore += m.score / 3 - 4
                        totalMissed += m.missed
                    } else {
                        return nil
                    }
                }

                return (item, FuzzyMatch(
                    score: totalScore + boost(item),
                    matched: matchedInName.sorted(),
                    missed: totalMissed
                ))
            }
            .sorted { a, b in
                if a.1.missed != b.1.missed { return a.1.missed < b.1.missed }
                if a.1.score != b.1.score { return a.1.score > b.1.score }
                return name(a.0).localizedCaseInsensitiveCompare(name(b.0)) == .orderedAscending
            }
    }

    private static func allowedMissCount(forQueryLength n: Int) -> Int {
        if n <= 4 { return 0 }
        if n <= 8 { return 1 }
        return 2
    }
}
