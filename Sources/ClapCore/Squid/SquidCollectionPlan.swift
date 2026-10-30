import Foundation

/// What sending a collection to a stick would do, worked out and checked before anything is written.
///
/// A collection with sub-collections becomes a new set, one bank per sub-collection (in the order given, named after it,
/// channels in sample order). A collection without any goes to the Pool as a new folder named after it, broken into
/// numbered folders when it holds more than a Pool folder can.
public struct SquidCollectionPlan: Equatable, Sendable {
    public struct Child: Equatable, Sendable {
        public var name: String
        public var samples: [Int64]
        public init(name: String, samples: [Int64]) { self.name = name; self.samples = samples }
    }
    public struct Bank: Equatable, Sendable {
        public var number: Int
        public var name: String
        public var samples: [Int64]
        public init(number: Int, name: String, samples: [Int64]) { self.number = number; self.name = name; self.samples = samples }
    }
    public struct PoolGroup: Equatable, Sendable {
        /// From the Pool down, as the folders are called on the stick.
        public var path: [String]
        public var samples: [Int64]
        public init(path: [String], samples: [Int64]) { self.path = path; self.samples = samples }
    }
    public enum Destination: Equatable, Sendable {
        case none
        case set(name: String, banks: [Bank])
        case pool(groups: [PoolGroup])
    }

    public var destination: Destination = .none
    /// Things to know; the send can go ahead.
    public var warnings: [String] = []
    /// Reasons nothing is sent.
    public var blockers: [String] = []
    public var isBlocked: Bool { !blockers.isEmpty || destination == .none }
    /// How many samples will be written (a sample in two banks counts twice).
    public var sampleCount: Int {
        switch destination {
        case .none: return 0
        case .set(_, let banks): return banks.reduce(0) { $0 + $1.samples.count }
        case .pool(let groups): return groups.reduce(0) { $0 + $1.samples.count }
        }
    }

    /// Every sample the plan writes, once.
    public var sampleIDs: [Int64] {
        var seen = Set<Int64>()
        let all: [Int64]
        switch destination {
        case .none: all = []
        case .set(_, let banks): all = banks.flatMap(\.samples)
        case .pool(let groups): all = groups.flatMap(\.samples)
        }
        return all.filter { seen.insert($0).inserted }
    }

    /// `ownSamples` are the ones put in the collection itself and `children` its sub-collections in sidebar order.
    public static func make(name: String, ownSamples: [Int64], children: [Child], contents: SquidStickContents) -> SquidCollectionPlan {
        children.isEmpty ? pool(name: name, samples: ownSamples, contents: contents)
                         : set(name: name, ownSamples: ownSamples, children: children, contents: contents)
    }

    private static func set(name: String, ownSamples: [Int64], children: [Child], contents: SquidStickContents) -> SquidCollectionPlan {
        var plan = SquidCollectionPlan()
        let report = SquidLayout.check(setName: name, existing: contents.sets.compactMap(\.name))
        plan.blockers += report.blockers
        plan.warnings += report.warnings
        if contents.namedSetCount >= SquidLayout.maxSets {
            plan.blockers.append("The module reads at most \(SquidLayout.maxSets) sets and the stick has \(contents.namedSetCount).")
        }
        var banks: [Bank] = []
        for child in children {
            if child.samples.isEmpty {
                plan.warnings.append("“\(child.name)” has no samples, so it gets no bank.")
                continue
            }
            if child.samples.count > SquidLayout.slotsPerBank {
                plan.blockers.append("“\(child.name)” has \(child.samples.count) samples, but a bank holds \(SquidLayout.slotsPerBank). "
                                     + "Move some into another sub-collection first.")
            }
            banks.append(Bank(number: banks.count + 1, name: child.name, samples: child.samples))
        }
        if banks.isEmpty { plan.blockers.append("The sub-collections have no samples to send.") }
        if banks.count > SquidLayout.maxBanksPerSet {
            plan.blockers.append("“\(name)” has \(banks.count) sub-collections, but a set holds \(SquidLayout.maxBanksPerSet) banks.")
        }
        for bank in banks {
            let bankReport = SquidLayout.check(bankName: bank.name)
            plan.warnings += bankReport.warnings.map { "Bank \(bank.number): \($0)" }
        }
        let inChildren = Set(children.flatMap(\.samples))
        let left = Set(ownSamples).subtracting(inChildren).count
        if left > 0 {
            plan.warnings.append("\(left) \(left == 1 ? "sample is" : "samples are") only in “\(name)” itself, not in a sub-collection, so "
                                 + "\(left == 1 ? "it is" : "they are") not sent.")
        }
        plan.destination = .set(name: name, banks: banks)
        return plan
    }

    private static func pool(name: String, samples: [Int64], contents: SquidStickContents) -> SquidCollectionPlan {
        var plan = SquidCollectionPlan()
        guard !samples.isEmpty else {
            plan.blockers.append("“\(name)” has no samples to send.")
            return plan
        }
        guard let folder = SquidLayout.poolPath(from: name).first else {
            plan.blockers.append("“\(name)” has no letters or numbers a Pool folder name can use.")
            return plan
        }
        if folder != name {
            plan.warnings.append("A Pool folder name can only hold letters, numbers, spaces, - and _, so the folder for “\(name)” is called “\(folder)”.")
        }
        if contents.poolFolder(at: [folder]) != nil {
            plan.blockers.append("The Pool already has a folder called “\(folder)”. Rename the collection or the folder, so the samples are not mixed in.")
            return plan
        }
        let size = SquidLayout.maxEntriesPerFolder
        if samples.count <= size {
            plan.destination = .pool(groups: [PoolGroup(path: [folder], samples: samples)])
            return plan
        }
        let parts = stride(from: 0, to: samples.count, by: size).map { Array(samples[$0..<min($0 + size, samples.count)]) }
        if parts.count > size {
            plan.blockers.append("A Pool folder holds \(size) entries, so \(samples.count) samples are too many even for numbered folders.")
            return plan
        }
        plan.destination = .pool(groups: parts.enumerated().map { PoolGroup(path: [folder, "\(folder) \($0.offset + 1)"], samples: $0.element) })
        plan.warnings.append("A Pool folder holds \(size) entries, so the samples go into \(parts.count) folders called “\(folder) 1” to “\(folder) \(parts.count)” inside “\(folder)”.")
        return plan
    }
}
