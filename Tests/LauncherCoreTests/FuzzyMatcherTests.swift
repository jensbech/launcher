import Testing
@testable import LauncherCore

struct FuzzyMatcherTests {
    private func items(_ names: [String]) -> [AppItem] {
        names.map { AppItem(id: $0, name: $0, path: "/Applications/\($0).app") }
    }

    @Test func emptyQuery_returnsNoResults() {
        #expect(FuzzyMatcher.search("", in: items(["Safari", "Mail"])) == [])
        #expect(FuzzyMatcher.search("   ", in: items(["Safari", "Mail"])) == [])
    }

    @Test func nonSubsequence_doesNotMatch() {
        #expect(FuzzyMatcher.score(query: "xyz", candidate: "Safari") == nil)
    }

    @Test func subsequence_matches() {
        #expect(FuzzyMatcher.score(query: "fgm", candidate: "Figma") != nil)
    }

    @Test func prefixMatch_outranksMidStringMatch() {
        let results = FuzzyMatcher.search("ma", in: items(["Activity Monitor", "Mail"]))
        #expect(results.first?.name == "Mail")
    }

    @Test func wordBoundary_scoresWell() {
        let results = FuzzyMatcher.search("am", in: items(["Activity Monitor", "Camera"]))
        #expect(results.first?.name == "Activity Monitor")
    }

    @Test func caseInsensitive() {
        #expect(FuzzyMatcher.score(query: "SAF", candidate: "safari") != nil)
    }

    @Test func tieBreak_isAlphabetical() {
        let results = FuzzyMatcher.search("a", in: items(["Avocado", "Apple"]))
        #expect(results.map(\.name) == ["Apple", "Avocado"])
    }

    @Test func matchedIndices_returnsSubsequencePositions() {
        #expect(FuzzyMatcher.matchedIndices(query: "fg", candidate: "Figma") == [0, 2])
    }

    @Test func matchedIndices_nilWhenNoMatch() {
        #expect(FuzzyMatcher.matchedIndices(query: "xyz", candidate: "Safari") == nil)
    }

    @Test func matchedIndices_emptyQueryReturnsEmpty() {
        #expect(FuzzyMatcher.matchedIndices(query: "", candidate: "Safari") == [])
    }

    @Test func boost_canReorderEqualMatches() {
        let apps = items(["Avocado", "Apple"])
        let boosted = FuzzyMatcher.search("a", in: apps) { $0.name == "Avocado" ? 100 : 0 }
        #expect(boosted.first?.name == "Avocado")
    }

    @Test func boost_doesNotMatchNonSubsequence() {
        let apps = items(["Safari"])
        let results = FuzzyMatcher.search("zzz", in: apps) { _ in 1000 }
        #expect(results.isEmpty)
    }
}
