import Foundation
import Testing
@testable import ClapCore

@Suite struct QueryRefinementTests {
    @Test func phrasesAreSplitAndSigned() {
        let r = QueryRefinement.parse("darker, no reverb; less distortion but more punch, -hiss, with warmth")
        #expect(r.positives == ["darker", "punch", "warmth"])
        #expect(r.negatives == ["reverb", "distortion", "hiss"])
        #expect(QueryRefinement.parse("  ,; ").isEmpty && QueryRefinement.parse("").isEmpty)
    }

    @Test func prefixesCombine() {
        #expect(QueryRefinement.parse("but no reverb") == QueryRefinement(negatives: ["reverb"]))
        #expect(QueryRefinement.parse("not no reverb") == QueryRefinement(positives: ["reverb"]), "a double negative adds")
        #expect(QueryRefinement.parse("not").phrases == ["not"], "a lone word is a phrase, not a prefix")
        #expect(QueryRefinement.parse("Nobody home").positives == ["Nobody home"], "\"no\" must be a whole word")
    }

    @Test func standardScoresAreComparable() {
        let z = QueryRefinement.standardised([1: 0.1, 2: 0.2, 3: 0.3])
        #expect(abs((z[1]! + z[2]! + z[3]!)) < 1e-5 && z[3]! > 0 && z[1]! < 0)
        #expect(QueryRefinement.standardised([1: 0.5]) == [1: 0])
        #expect(QueryRefinement.standardised([:]).isEmpty)
    }

    @Test func wordsPullTheRankingTowardsWhatWasAsked() {
        // Three samples equally like the sound; the first is also dark, the second reverberant.
        let base: [Int64: Float] = [1: 0.8, 2: 0.8, 3: 0.8, 4: 0.2, 5: 0.2]
        let dark: [Int64: Float] = [1: 0.3, 2: 0.1, 3: 0.1, 4: 0.1, 5: 0.1]
        let reverb: [Int64: Float] = [1: 0.1, 2: 0.3, 3: 0.1, 4: 0.1, 5: 0.1]
        let order = { (scores: [Int64: Float]) in scores.sorted { $0.value > $1.value }.map(\.key) }
        let plain = QueryRefinement.combine(base: base, positives: [], negatives: [])
        #expect(Set(order(plain).prefix(3)) == [1, 2, 3])
        let withDark = QueryRefinement.combine(base: base, positives: [dark], negatives: [])
        #expect(order(withDark).first == 1)
        let noReverb = QueryRefinement.combine(base: base, positives: [], negatives: [reverb])
        #expect(noReverb[2]! < noReverb[3]!, "the reverberant one drops below its equal")
        let both = QueryRefinement.combine(base: base, positives: [dark], negatives: [reverb])
        #expect(order(both).prefix(3).elementsEqual([1, 3, 2]))
    }

    @Test func wordsDoNotPullInSoundsUnlikeTheOriginal() {
        var base: [Int64: Float] = [:], dark: [Int64: Float] = [:]
        for id in 1...50 { base[Int64(id)] = 0.9 - Float(id) * 0.001; dark[Int64(id)] = 0.1 }
        for id in 51...100 { base[Int64(id)] = 0.1; dark[Int64(id)] = 0.9 }     // very dark, but nothing like the sound
        let combined = QueryRefinement.combine(base: base, positives: [dark], negatives: [], candidates: 50)
        #expect(combined.count == 50 && combined.keys.allSatisfy { $0 <= 50 })
    }

    @Test func samplesWithoutASoundScoreAreNotInvented() {
        let combined = QueryRefinement.combine(base: [1: 0.9, 2: 0.5], positives: [[1: 0.2, 2: 0.1, 99: 0.9]], negatives: [])
        #expect(combined.keys.sorted() == [1, 2])
    }
}
