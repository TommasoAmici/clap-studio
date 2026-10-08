import ClapCore
import Foundation

/// A small step sequencer for trying samples together. It follows the project tempo and takes its sounds from
/// the selection, the tray or the kit builder.
extension AppModel {
    /// Tempo the drum machine plays at: the project's, or a neutral 120 when none is set.
    var drumTempo: Double { project.bpm ?? DrumTiming.defaultBPM }

    func makeDrumMachine() -> DrumMachine {
        let machine = DrumMachine(cache: player.cache)
        machine.bpm = drumTempo
        machine.onStep = { [weak self] step in
            MainActor.assumeIsolated { if self?.drumPlaying == true { self?.drumStep = step } }
        }
        machine.onRunningChange = { [weak self] running in
            MainActor.assumeIsolated {
                self?.drumPlaying = running
                if !running { self?.drumStep = nil }
            }
        }
        return machine
    }

    /// Sends the current pattern, and the files it needs, to the engine.
    func pushDrumPattern() {
        var urls: [Int64: URL] = [:]
        for track in drumPattern.tracks {
            if let sample = sampleByID[track.sampleID] { urls[track.sampleID] = sample.url }
        }
        drumMachine.update(pattern: drumPattern, urls: urls)
    }

    func toggleDrumPlayback() {
        if drumPlaying { drumMachine.stop(); return }
        pushDrumPattern()
        drumMachine.bpm = drumTempo
        drumMachine.start()
    }

    /// Adds samples as new tracks (up to the track limit), each with a starter rhythm for its category.
    func addToDrums(_ ids: [Int64]) {
        var pattern = drumPattern
        var skipped = 0
        for id in ids {
            guard let sample = sampleByID[id], !pattern.tracks.contains(where: { $0.sampleID == id }) else { continue }
            if !pattern.addTrack(sampleID: id, label: sample.name, category: sample.effectiveCategory) { skipped += 1 }
        }
        drumPattern = pattern
        showDrums = true
        if skipped > 0 { errorMessage = "The drum machine holds \(DrumPattern.maxTracks) sounds. \(skipped) were left out." }
    }

    /// Replaces the pattern with the kit builder's current picks, each keeping its alternatives for swapping.
    func loadKitIntoDrums() {
        var pattern = DrumPattern(swing: drumPattern.swing)
        for slot in kitSlots {
            guard let pick = kitPick(slot) else { continue }
            pattern.addTrack(sampleID: pick.id, label: slot.category, category: slot.category, alternatives: slot.candidates)
        }
        drumPattern = pattern
        showDrums = true
    }

    /// Steps a track through its alternatives (or, without any, does nothing) and auditions the new sound.
    func cycleDrumSample(track index: Int, by step: Int) {
        guard drumPattern.tracks.indices.contains(index) else { return }
        let track = drumPattern.tracks[index]
        guard track.alternatives.count > 1 else { return }
        let current = track.alternatives.firstIndex(of: track.sampleID) ?? 0
        let next = track.alternatives[(current + step + track.alternatives.count) % track.alternatives.count]
        drumPattern.replaceSample(track: index, with: next)
        select(next, play: true)
    }

    /// Puts the selected sample on a track in place of its current sound.
    func replaceDrumSample(track index: Int, with id: Int64) {
        drumPattern.replaceSample(track: index, with: id)
    }

    func drumSampleName(_ track: DrumTrack) -> String { sampleByID[track.sampleID]?.name ?? "Missing sample" }
}
