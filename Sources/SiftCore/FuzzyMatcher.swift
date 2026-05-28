import Foundation

public struct FuzzyMatcher {
    public static func score(query: String, candidate: String) -> Int? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return nil }
        var qi = 0
        var total = 0
        var prevMatch = -2
        for ci in c.indices {
            guard qi < q.count, c[ci] == q[qi] else { continue }
            var bonus = 1
            if ci == 0 {
                bonus += 12
            } else {
                let prev = c[ci - 1]
                if prev == " " || prev == "-" || prev == "_" || prev == "." {
                    bonus += 7
                }
            }
            if prevMatch == ci - 1 {
                bonus += 5
            }
            total += bonus
            prevMatch = ci
            qi += 1
        }
        return qi == q.count ? total : nil
    }

    public static func matchedIndices(query: String, candidate: String) -> [Int]? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return [] }
        var qi = 0
        var indices: [Int] = []
        for ci in c.indices {
            guard qi < q.count, c[ci] == q[qi] else { continue }
            indices.append(ci)
            qi += 1
        }
        return qi == q.count ? indices : nil
    }

    public static func search(
        _ query: String,
        in items: [AppItem],
        boost: (AppItem) -> Int = { _ in 0 }
    ) -> [AppItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return items
            .compactMap { item -> (AppItem, Int)? in
                guard let s = score(query: trimmed, candidate: item.name) else { return nil }
                return (item, s + boost(item))
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }
            .map { $0.0 }
    }
}
