import Testing
@testable import SiftCore

struct FuzzyMatcherTests {
    private func items(_ names: [String]) -> [AppItem] {
        names.map { AppItem(id: $0, name: $0, path: "/Applications/\($0).app") }
    }

    private func names(_ results: [(AppItem, FuzzyMatch)]) -> [String] {
        results.map { $0.0.name }
    }

    @Test func emptyQuery_returnsNoResults() {
        #expect(FuzzyMatcher.search("", in: items(["Safari", "Mail"])).isEmpty)
        #expect(FuzzyMatcher.search("   ", in: items(["Safari", "Mail"])).isEmpty)
    }

    @Test func nonSubsequenceShort_doesNotMatch() {
        #expect(FuzzyMatcher.score(query: "xyz", candidate: "Safari") == nil)
    }

    @Test func subsequence_matches() {
        #expect(FuzzyMatcher.score(query: "fgm", candidate: "Figma") != nil)
    }

    @Test func prefixMatch_outranksMidStringMatch() {
        let results = FuzzyMatcher.search("ma", in: items(["Activity Monitor", "Mail"]))
        #expect(names(results).first == "Mail")
    }

    @Test func wordBoundary_scoresWell() {
        let results = FuzzyMatcher.search("am", in: items(["Activity Monitor", "Camera"]))
        #expect(names(results).first == "Activity Monitor")
    }

    @Test func caseInsensitive() {
        #expect(FuzzyMatcher.score(query: "SAF", candidate: "safari") != nil)
    }

    @Test func tieBreak_isAlphabetical() {
        let results = FuzzyMatcher.search("a", in: items(["Avocado", "Apple"]))
        #expect(names(results) == ["Apple", "Avocado"])
    }

    @Test func matchedIndices_returnsSubsequencePositions() {
        #expect(FuzzyMatcher.matchedIndices(query: "fg", candidate: "Figma") == [0, 2])
    }

    @Test func matchedIndices_nilWhenWayOff() {
        #expect(FuzzyMatcher.matchedIndices(query: "xyz", candidate: "Safari") == nil)
    }

    @Test func matchedIndices_emptyQueryReturnsNil() {
        #expect(FuzzyMatcher.matchedIndices(query: "", candidate: "Safari") == nil)
    }

    @Test func boost_canReorderEqualMatches() {
        let apps = items(["Avocado", "Apple"])
        let boosted = FuzzyMatcher.search("a", in: apps) { $0.name == "Avocado" ? 100 : 0 }
        #expect(names(boosted).first == "Avocado")
    }

    @Test func boost_doesNotMatchNonSubsequenceShortQuery() {
        let apps = items(["Safari"])
        let results = FuzzyMatcher.search("zzz", in: apps) { _ in 1000 }
        #expect(results.isEmpty)
    }

    @Test func typoTolerant_returnsApproximateForLongerQuery() {
        // "gitcardrback" has an extra 'r' typo; should still match "GiftCard Backoffice"
        let match = FuzzyMatcher.match(query: "giftcardrback", candidate: "Gift Cards Backoffice")
        #expect(match != nil)
        #expect((match?.missed ?? 0) > 0)
    }

    @Test func exactMatch_outranksApproximate() {
        let pool = items(["GiftCard Backoffice", "Gibberish"])
        let results = FuzzyMatcher.search("giftcardrback", in: pool)
        #expect(names(results).first == "GiftCard Backoffice")
        #expect(results.first?.1.missed == 1)
    }
}
