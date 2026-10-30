import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidChannelPlanTests {
    private func slots(_ plan: SquidChannelPlan) -> [[Int]?] { plan.slots.map { $0.map { [$0.bank, $0.channel] } } }

    @Test func samplesFillTheChannelsOfOneBankInOrder() {
        let plan = SquidChannelPlan.make(overrides: [nil, nil, nil], rule: .fillBank, startBank: 4, filled: [:])
        #expect(slots(plan) == [[4, 1], [4, 2], [4, 3]], "Without any choice the samples take channels 1, 2, 3 of the chosen bank.")
        #expect(plan.issues.isEmpty)
    }

    @Test func addingSkipsChannelsThatAlreadyHoldASample() {
        let plan = SquidChannelPlan.make(overrides: [nil, nil], rule: .fillBank, startBank: 1, filled: [1: [1, 3]])
        #expect(slots(plan) == [[1, 2], [1, 4]], "Existing samples are never overwritten, so the free channels are used.")
    }

    @Test func aChosenChannelWinsAndTheOthersFillTheGaps() {
        let plan = SquidChannelPlan.make(overrides: [nil, 5, nil], rule: .fillBank, startBank: 1, filled: [:])
        #expect(slots(plan) == [[1, 1], [1, 5], [1, 2]], "Samples without a choice take the lowest channels nobody asked for.")
    }

    @Test func twoSamplesOnOneChannelIsABlockingProblem() {
        let plan = SquidChannelPlan.make(overrides: [3, 3], rule: .fillBank, startBank: 1, filled: [:])
        #expect(plan.issues.contains(.duplicateChannel(bank: 1, channel: 3)))
        #expect(plan.isBlocked, "One of the two would silently replace the other.")
    }

    @Test func aChosenChannelThatIsTakenIsABlockingProblem() {
        let plan = SquidChannelPlan.make(overrides: [2], rule: .fillBank, startBank: 1, filled: [1: [2]])
        #expect(plan.issues.contains(.channelTaken(bank: 1, channel: 2)))
        #expect(plan.isBlocked)
    }

    @Test func replacingABankIgnoresWhatItHolds() {
        let plan = SquidChannelPlan.make(overrides: [nil, 2], rule: .fillBank, startBank: 1, filled: [1: [1, 2]],
                                         replacingStartBank: true)
        #expect(slots(plan) == [[1, 1], [1, 2]])
        #expect(!plan.isBlocked, "A replaced bank goes to the Trash first, so its channels are free.")
    }

    @Test func moreSamplesThanChannelsAreLeftOutWithANote() {
        let plan = SquidChannelPlan.make(overrides: Array(repeating: nil, count: 10), rule: .fillBank, startBank: 1, filled: [:])
        #expect(plan.slots.compactMap { $0 }.count == 8 && plan.slots[8] == nil && plan.slots[9] == nil)
        #expect(plan.issues == [.doesNotFit(count: 2)])
        #expect(!plan.isBlocked, "Like before, the first eight are sent and the rest are marked as not sent.")
    }

    @Test func theSameChannelOfFollowingBanks() {
        let plan = SquidChannelPlan.make(overrides: [nil, nil, nil, nil], rule: .sameChannel(2), startBank: 1, filled: [:])
        #expect(slots(plan) == [[1, 2], [2, 2], [3, 2], [4, 2]], "Four snares on channel 2 of banks 1 to 4.")
    }

    @Test func aBankWhoseChannelIsTakenIsSkipped() {
        let plan = SquidChannelPlan.make(overrides: [nil, nil, nil], rule: .sameChannel(2), startBank: 1, filled: [2: [2], 3: [1]])
        #expect(slots(plan) == [[1, 2], [3, 2], [4, 2]], "Bank 2 has a sample on channel 2; bank 3 only uses channel 1.")
        #expect(plan.issues == [.skippedBank(bank: 2, channel: 2)], "The skip is reported, not silent.")
        #expect(!plan.isBlocked)
    }

    @Test func aSampleCanOverrideTheChannelInTheSameChannelMode() {
        let plan = SquidChannelPlan.make(overrides: [nil, 4, nil], rule: .sameChannel(2), startBank: 1, filled: [:])
        #expect(slots(plan) == [[1, 2], [2, 4], [3, 2]])
    }

    @Test func runningOutOfBanksStopsTheSend() {
        let plan = SquidChannelPlan.make(overrides: [nil, nil, nil, nil], rule: .sameChannel(1), startBank: 98, filled: [:])
        #expect(slots(plan) == [[98, 1], [99, 1], nil, nil])
        #expect(plan.issues == [.notEnoughBanks(missing: 2)])
        #expect(plan.isBlocked, "Sending part of the samples would leave the rest silently behind.")
    }

    @Test func messagesSayWhatIsWrongInPlainWords() {
        #expect(SquidPlanIssue.duplicateChannel(bank: 2, channel: 3).message.contains("channel 3"))
        #expect(SquidPlanIssue.notEnoughBanks(missing: 2).message.contains("2"))
    }
}
