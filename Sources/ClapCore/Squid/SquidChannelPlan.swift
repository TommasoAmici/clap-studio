import Foundation

/// One channel of one bank.
public struct SquidSlot: Hashable, Sendable {
    public var bank: Int
    public var channel: Int
    public init(bank: Int, channel: Int) { self.bank = bank; self.channel = channel }
}

/// Where samples go when no channel is chosen for them.
public enum SquidChannelRule: Equatable, Sendable {
    /// Channels 1, 2, 3… of one bank (the free ones, when adding to a bank that already has samples).
    case fillBank
    /// This channel of the chosen bank, then of the next bank, and so on.
    case sameChannel(Int)
}

/// Something to tell the musician about a plan. Blocking ones stop the send; the others only explain.
/// Following the same channel through the banks replaces what is there (with a warning); picking a taken channel by hand
/// while adding to one bank still stops the send, because that bank can be replaced as a whole instead.
public enum SquidPlanIssue: Equatable, Sendable {
    case duplicateChannel(bank: Int, channel: Int)
    case channelTaken(bank: Int, channel: Int)
    case doesNotFit(count: Int)
    /// The channel already holds a sample and the new one replaces it.
    case overwritesChannel(bank: Int, channel: Int)
    case notEnoughBanks(missing: Int)

    public var isBlocking: Bool {
        switch self {
        case .duplicateChannel, .channelTaken, .notEnoughBanks: return true
        case .doesNotFit, .overwritesChannel: return false
        }
    }

    public var message: String {
        switch self {
        case .duplicateChannel(let bank, let channel):
            return "Two samples are set to channel \(channel) of bank \(bank). Give each sample its own channel."
        case .channelTaken(let bank, let channel):
            return "Channel \(channel) of bank \(bank) already holds a sample. Pick another channel; nothing is overwritten."
        case .doesNotFit(let count):
            return "\(count) \(count == 1 ? "sample does" : "samples do") not fit in the bank's free channels and \(count == 1 ? "is" : "are") not sent."
        case .overwritesChannel(let bank, let channel):
            return "Bank \(bank): channel \(channel) already holds a sample and will be overwritten."
        case .notEnoughBanks(let missing):
            return "A set holds \(SquidLayout.maxBanksPerSet) banks, so \(missing) \(missing == 1 ? "sample does" : "samples do") not fit. Nothing was sent."
        }
    }
}

/// Which bank and channel each sample goes to, worked out before anything is written.
public struct SquidChannelPlan: Equatable, Sendable {
    /// One entry per sample, in order; nil when the sample has nowhere to go.
    public var slots: [SquidSlot?] = []
    public var issues: [SquidPlanIssue] = []
    public var isBlocked: Bool { issues.contains(where: \.isBlocking) }
    /// The issues as the sheet lists them: the ones that stop the send first, so a long scrolled list never hides them.
    public var orderedIssues: [SquidPlanIssue] { issues.filter(\.isBlocking) + issues.filter { !$0.isBlocking } }

    /// `overrides` holds the channel chosen for each sample (nil: decide for it). `filled` maps the banks already on the
    /// stick to the channels that hold a sample; a bank that is not there yet is missing from it. `replacingStartBank`
    /// treats the first bank as empty because it is going to the Trash first.
    public static func make(overrides: [Int?], rule: SquidChannelRule, startBank: Int, filled: [Int: Set<Int>],
                            replacingStartBank: Bool = false) -> SquidChannelPlan {
        var plan = SquidChannelPlan(slots: Array(repeating: nil, count: overrides.count))
        let channels = 1...SquidLayout.slotsPerBank
        let chosen = overrides.map { $0.flatMap { channels.contains($0) ? $0 : nil } }
        guard (1...SquidLayout.maxBanksPerSet).contains(startBank) else {
            plan.issues = [.notEnoughBanks(missing: overrides.count)]
            return plan
        }
        switch rule {
        case .fillBank:
            let taken: Set<Int> = replacingStartBank ? [] : (filled[startBank] ?? [])
            var claimed = Set<Int>()
            for (index, channel) in chosen.enumerated() {
                guard let channel else { continue }
                plan.slots[index] = SquidSlot(bank: startBank, channel: channel)
                if taken.contains(channel) { plan.issues.append(.channelTaken(bank: startBank, channel: channel)) }
                else if !claimed.insert(channel).inserted { plan.issues.append(.duplicateChannel(bank: startBank, channel: channel)) }
            }
            var free = channels.filter { !taken.contains($0) && !claimed.contains($0) }[...]
            var left = 0
            for index in chosen.indices where chosen[index] == nil {
                if let channel = free.popFirst() { plan.slots[index] = SquidSlot(bank: startBank, channel: channel) } else { left += 1 }
            }
            if left > 0 { plan.issues.append(.doesNotFit(count: left)) }
        case .sameChannel(let fallback):
            let standard = channels.contains(fallback) ? fallback : 1
            var bank = startBank
            var missing = 0
            for (index, channel) in chosen.enumerated() {
                let channel = channel ?? standard
                if bank > SquidLayout.maxBanksPerSet { missing += 1; continue }
                if filled[bank]?.contains(channel) == true { plan.issues.append(.overwritesChannel(bank: bank, channel: channel)) }
                plan.slots[index] = SquidSlot(bank: bank, channel: channel)
                bank += 1
            }
            if missing > 0 { plan.issues.append(.notEnoughBanks(missing: missing)) }
        }
        return plan
    }
}
