import ClapCore
import Foundation

/// Trying other sounds on the drum machine's tracks: one track at a time, or the whole kit, always with sounds that
/// fill the same role and sound close to what they replace.
extension AppModel {
    var canShuffleDrums: Bool { drumPattern.tracks.contains { !$0.locked } }

    /// Puts a similar sound on the track. Returns whether one was found.
    @discardableResult
    func swapDrumSound(track index: Int, audition: Bool = true) -> Bool {
        guard drumPattern.tracks.indices.contains(index), let id = nextDrumSound(for: index) else { return false }
        drumPattern.replaceSample(track: index, with: id)
        if audition { select(id, play: !drumPlaying) }
        return true
    }

    /// Swaps every track that is not locked, then lets the pattern play (or previews nothing if it is stopped).
    func shuffleDrumKit() {
        var swapped = 0
        for index in drumPattern.tracks.indices where !drumPattern.tracks[index].locked {
            if swapDrumSound(track: index, audition: false) { swapped += 1 }
        }
        if swapped == 0 {
            errorMessage = drumPattern.tracks.allSatisfy(\.locked)
                ? "Every track is locked." : "No other sounds in the library fit these tracks."
        } else if !drumPlaying { toggleDrumPlayback() }
    }

    /// Takes the track back to the sound it had before its last swap.
    func undoDrumSwap(track index: Int) {
        guard let id = drumPattern.restorePreviousSample(track: index) else { return }
        select(id, play: !drumPlaying)
    }

    func toggleDrumLock(track index: Int) {
        guard drumPattern.tracks.indices.contains(index) else { return }
        drumPattern.tracks[index].locked.toggle()
    }

    private func nextDrumSound(for index: Int) -> Int64? {
        let track = drumPattern.tracks[index]
        guard let reference = sampleByID[track.sampleID] else { return nil }
        let used = Set(drumPattern.tracks.map(\.sampleID))
        var generator = SystemRandomNumberGenerator()
        return DrumSwap.next(for: reference, history: track.history, spread: drumVariation.spread, index: snapshot?.index,
                             weights: aspectWeights, samples: samples, lookup: { [sampleByID] in sampleByID[$0] },
                             excluding: used, using: &generator)
    }
}
