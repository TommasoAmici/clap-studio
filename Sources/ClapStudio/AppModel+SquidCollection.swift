import ClapCore
import Foundation

/// Sending a whole collection to a stick.
extension AppModel {
    /// What a collection holds, for the planner: its own samples and each sub-collection in sidebar order. Samples that left the library are left out.
    struct SquidCollectionInput: Equatable {
        var name: String
        var own: [Int64]
        var children: [SquidCollectionPlan.Child]
    }

    func squidCollectionInput(_ id: Int64) -> SquidCollectionInput? {
        guard let node = collectionTree.first(where: { $0.id == id }) ?? collectionTree.lazy.compactMap({ $0.children?.first { $0.id == id } }).first
        else { return nil }
        func members(_ id: Int64) -> [Int64] { (store?.collectionMembers(id: id) ?? []).filter { sampleByID[$0] != nil } }
        return SquidCollectionInput(name: node.record.name, own: members(id),
                                    children: (node.children ?? []).map { .init(name: $0.record.name, samples: members($0.id)) })
    }

    func openSquidCollection(_ id: Int64) {
        guard squidEnabled else { return }
        squidCollectionID = id
    }

    /// Writes the plan to the drive, then refreshes what the app shows of it. Returns an error message, or nil on success.
    func sendCollectionToSquid(_ plan: SquidCollectionPlan, driveID: String) async -> String? {
        guard let drive = drive(id: driveID) else { return "The drive is no longer connected." }
        var sources: [Int64: SquidSource] = [:]
        for bank in plan.sampleIDs { sources[bank] = squidSource(for: bank) }
        let volume = drive.url
        let outcome: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            do {
                try SquidCollectionSender.send(plan, sources: sources, toVolume: volume)
                return .success(())
            } catch { return .failure(error) }
        }.value
        if case .failure(let error) = outcome {
            return "Could not send the collection: \(error.localizedDescription) Your library files were only read, never changed."
        }
        return finishSquidWrite(outcome, volume: volume)
    }
}
