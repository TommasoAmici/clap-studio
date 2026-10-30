import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidCollectionPlanTests {
    private func ids(_ range: ClosedRange<Int>) -> [Int64] { range.map(Int64.init) }
    private func child(_ name: String, _ range: ClosedRange<Int>) -> SquidCollectionPlan.Child { .init(name: name, samples: ids(range)) }
    private func banks(_ plan: SquidCollectionPlan) -> [SquidCollectionPlan.Bank] {
        if case .set(_, let banks) = plan.destination { return banks }
        return []
    }
    private func groups(_ plan: SquidCollectionPlan) -> [SquidCollectionPlan.PoolGroup] {
        if case .pool(let groups) = plan.destination { return groups }
        return []
    }

    @Test func eachSubCollectionBecomesABankOfANewSetNamedAfterTheCollection() {
        let plan = SquidCollectionPlan.make(name: "Party", ownSamples: [], children: [child("Opening", 1...3), child("Peak", 4...8)],
                                            contents: SquidStickContents())
        #expect(plan.destination == .set(name: "Party", banks: [
            .init(number: 1, name: "Opening", samples: ids(1...3)), .init(number: 2, name: "Peak", samples: ids(4...8)),
        ]), "Banks follow the sidebar order and take the sub-collection's name; channels follow its sample order.")
        #expect(plan.blockers.isEmpty && plan.sampleCount == 8)
    }

    @Test func samplesOnlyInTheParentAreLeftOutAndSaid() {
        let plan = SquidCollectionPlan.make(name: "Party", ownSamples: ids(1...5), children: [child("Opening", 1...2)], contents: SquidStickContents())
        #expect(banks(plan).count == 1 && banks(plan)[0].samples == ids(1...2))
        #expect(plan.warnings.contains { $0.contains("3 samples") && $0.contains("Party") }, "Three samples are only in the parent, so they are not sent.")
        let covered = SquidCollectionPlan.make(name: "Party", ownSamples: ids(1...2), children: [child("Opening", 1...2)], contents: SquidStickContents())
        #expect(covered.warnings.isEmpty, "A parent sample that is also in a sub-collection is sent with it.")
    }

    @Test func aSubCollectionOverEightStopsEverything() {
        let plan = SquidCollectionPlan.make(name: "Party", ownSamples: [], children: [child("Opening", 1...3), child("Peak", 4...12)],
                                            contents: SquidStickContents())
        #expect(plan.isBlocked)
        #expect(plan.blockers.contains { $0.contains("Peak") && $0.contains("9 samples") && $0.contains("8") })
        #expect(!plan.blockers.contains { $0.contains("Opening") })
    }

    @Test func anEmptySubCollectionGetsNoBankAndNumberingContinues() {
        let plan = SquidCollectionPlan.make(name: "Party", ownSamples: [], children: [SquidCollectionPlan.Child(name: "Empty", samples: []), child("Peak", 1...2)],
                                            contents: SquidStickContents())
        #expect(banks(plan).map(\.number) == [1] && banks(plan)[0].name == "Peak")
        #expect(plan.warnings.contains { $0.contains("Empty") })
        let nothing = SquidCollectionPlan.make(name: "Party", ownSamples: [], children: [SquidCollectionPlan.Child(name: "Empty", samples: [])], contents: SquidStickContents())
        #expect(nothing.isBlocked, "There is nothing to send.")
    }

    @Test func theSetNameFollowsTheSetRulesWithoutBeingChanged() {
        let existing = SquidStickContents(hasSquidFolder: true, sets: [SquidSet(name: nil, banks: []), SquidSet(name: "party", banks: [])])
        let clash = SquidCollectionPlan.make(name: "Party", ownSamples: [], children: [child("A", 1...2)], contents: existing)
        #expect(clash.isBlocked && clash.blockers.contains { $0.contains("already exists") }, "A new set never reuses a set that is on the stick.")
        let long = SquidCollectionPlan.make(name: "Summer Party", ownSamples: [], children: [child("A", 1...2)], contents: SquidStickContents())
        #expect(!long.isBlocked && long.warnings.contains { $0.contains("12 characters") }, "Too long for the module is a warning, kept as typed.")
        #expect(long.destination == .set(name: "Summer Party", banks: [.init(number: 1, name: "A", samples: ids(1...2))]))
        let bad = SquidCollectionPlan.make(name: "A/B", ownSamples: [], children: [child("A", 1...2)], contents: SquidStickContents())
        #expect(bad.isBlocked, "A folder cannot hold a slash.")
        let full = SquidStickContents(hasSquidFolder: true, sets: (1...16).map { SquidSet(name: "S\($0)", banks: []) })
        #expect(SquidCollectionPlan.make(name: "New", ownSamples: [], children: [child("A", 1...2)], contents: full).isBlocked,
                "The module reads at most 16 sets.")
    }

    @Test func bankNamesAreWarnedAboutNotChanged() {
        let plan = SquidCollectionPlan.make(name: "Party", ownSamples: [], children: [child("Opening act", 1...2)], contents: SquidStickContents())
        #expect(banks(plan)[0].name == "Opening act")
        #expect(plan.warnings.contains { $0.contains("Bank 1") && $0.contains("Opening") }, "The module shows 8 characters of a bank name.")
    }

    @Test func aSetHoldsAtMostNinetyNineBanks() {
        let many = (1...100).map { child("C\($0)", 1...1) }
        let plan = SquidCollectionPlan.make(name: "Big", ownSamples: [], children: many, contents: SquidStickContents())
        #expect(plan.isBlocked && plan.blockers.contains { $0.contains("99") })
    }

    @Test func aPlainCollectionBecomesAPoolFolderNamedAfterIt() {
        let plan = SquidCollectionPlan.make(name: "Breaks 707", ownSamples: ids(1...40), children: [], contents: SquidStickContents())
        #expect(plan.destination == .pool(groups: [.init(path: ["Breaks 707"], samples: ids(1...40))]))
        #expect(plan.warnings.isEmpty && !plan.isBlocked)
    }

    @Test func aPoolNameThatMustBeCleanedIsSaidSoAndNeverSilentlyChanged() {
        let plan = SquidCollectionPlan.make(name: "Party #23", ownSamples: ids(1...2), children: [], contents: SquidStickContents())
        #expect(groups(plan).first?.path == ["Party 23"])
        #expect(plan.warnings.contains { $0.contains("Party #23") && $0.contains("Party 23") })
    }

    @Test func tooManyForOnePoolFolderBreaksIntoNumberedFolders() {
        let plan = SquidCollectionPlan.make(name: "Loops", ownSamples: ids(1...600), children: [], contents: SquidStickContents())
        #expect(groups(plan).map(\.path) == [["Loops", "Loops 1"], ["Loops", "Loops 2"], ["Loops", "Loops 3"]])
        #expect(groups(plan).map(\.samples.count) == [256, 256, 88], "A Pool folder holds 256 entries; the samples keep their order.")
        #expect(groups(plan)[2].samples.first == 513)
        #expect(plan.warnings.contains { $0.contains("3 folders") })
        let exact = SquidCollectionPlan.make(name: "Loops", ownSamples: ids(1...256), children: [], contents: SquidStickContents())
        #expect(groups(exact).map(\.path) == [["Loops"]], "256 still fit in one folder.")
    }

    @Test func aPoolFolderThatIsAlreadyThereIsNotMixedIn() {
        let contents = SquidStickContents(hasSquidFolder: true, hasPool: true, poolFolders: [SquidPoolFolder(name: "loops", path: ["loops"], sampleCount: 3)])
        let plan = SquidCollectionPlan.make(name: "Loops", ownSamples: ids(1...5), children: [], contents: contents)
        #expect(plan.isBlocked && plan.blockers.contains { $0.contains("already") }, "Folder names match without regard to case, as on the stick.")
    }

    @Test func anEmptyCollectionHasNothingToSend() {
        #expect(SquidCollectionPlan.make(name: "Empty", ownSamples: [], children: [], contents: SquidStickContents()).isBlocked)
    }
}
