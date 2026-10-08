import ClapCore
import Foundation

extension AppModel {
    /// Opens the kit builder around a sample.
    func buildKit(around id: Int64) {
        guard let snapshot, let anchor = sampleByID[id] else {
            errorMessage = "The kit builder needs the library to be indexed and the map built."
            return
        }
        kitSlots = KitBuilder.suggest(anchor: anchor, samples: samples, index: snapshot.index)
        kitChoice = [:]
        showKit = true
    }

    /// The sample currently chosen for a slot.
    func kitPick(_ slot: KitSlot) -> SampleRecord? {
        let i = min(kitChoice[slot.category] ?? 0, slot.candidates.count - 1)
        return slot.candidates.indices.contains(i) ? sampleByID[slot.candidates[i]] : nil
    }

    func cycleKit(_ slot: KitSlot, by step: Int) {
        guard slot.candidates.count > 1 else { return }
        let current = kitChoice[slot.category] ?? 0
        let next = (current + step + slot.candidates.count) % slot.candidates.count
        kitChoice[slot.category] = next
        if let pick = kitPick(slot) { select(pick.id, play: true) }
    }

    var kitSamples: [SampleRecord] { kitSlots.compactMap(kitPick) }
}
