import Testing
@testable import ClapCore

@Suite struct SeededShuffleTests {
    private let ids = Array(Int64(1)...200)

    @Test func sameSeedSameOrder() {
        #expect(SeededShuffle.order(ids, seed: 7, id: { $0 }) == SeededShuffle.order(ids, seed: 7, id: { $0 }))
    }

    @Test func newSeedNewOrderWithTheSameItems() {
        let a = SeededShuffle.order(ids, seed: 1, id: { $0 })
        let b = SeededShuffle.order(ids, seed: 2, id: { $0 })
        #expect(a != b)
        #expect(a != ids, "it really is shuffled")
        #expect(a.sorted() == ids && b.sorted() == ids, "nothing lost or repeated")
    }

    @Test func removingAnItemKeepsTheRestInPlace() {
        let full = SeededShuffle.order(ids, seed: 9, id: { $0 })
        let without = SeededShuffle.order(ids.filter { $0 != 50 }, seed: 9, id: { $0 })
        #expect(full.filter { $0 != 50 } == without)
    }

    @Test func sampleFromAWideSpreadComesFirst() {
        // Over many seeds every item should lead sometimes (no fixed favourites at the top).
        let leaders = Set((1...300).map { SeededShuffle.order(Array(Int64(1)...10), seed: UInt64($0), id: { $0 }).first! })
        #expect(leaders.count >= 8)
    }
}
