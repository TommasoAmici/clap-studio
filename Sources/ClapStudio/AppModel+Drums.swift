import ClapCore
import Foundation

/// A small step sequencer for trying samples together. It follows the project tempo and takes its sounds from
/// the selection or the kit builder.
extension AppModel {
    /// Tempo the drum machine plays at: the project's, or a neutral 120 when none is set.
    var drumTempo: Double { project.bpm ?? DrumTiming.defaultBPM }

    var drumPreset: DrumPreset? { DrumPreset.preset(id: drumPresetID) }

    private static let drumPresetKey = "drum.preset"

    func loadDrumPreset() {
        // Assigned through the setter, which saves it again: harmless, and an id that no longer exists is dropped.
        let id = UserDefaults.standard.string(forKey: Self.drumPresetKey)
        drumPresetID = DrumPreset.preset(id: id)?.id
    }

    func saveDrumPreset() {
        if let drumPresetID { UserDefaults.standard.set(drumPresetID, forKey: Self.drumPresetKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.drumPresetKey) }
    }

    /// Picks a groove: the project takes its tempo (loop matching and previews follow it), the pattern takes its
    /// swing and a rhythm for each track. nil goes back to the plain starter rhythms, which leaves the tempo as it is.
    func selectDrumPreset(_ id: String?) {
        drumPresetID = id
        guard let preset = drumPreset else { return }
        project.bpm = preset.bpm
        var pattern = drumPattern
        pattern.apply(preset)
        drumPattern = pattern
    }

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
        var sources: [Int64: DrumSource] = [:]
        for track in drumPattern.tracks {
            if let sample = sampleByID[track.sampleID] { sources[track.sampleID] = DrumSource(url: sample.url, trim: activeTrim(for: sample)) }
        }
        drumMachine.update(pattern: drumPattern, sources: sources)
    }

    /// Which samples are loaded in the drum machine (shown highlighted in the Library and on the map). Only assigned
    /// when it changes, so toggling steps does not redraw the list.
    func updateDrumTracks() {
        var tracks: [Int64: Int] = [:]
        for (index, track) in drumPattern.tracks.enumerated() where tracks[track.sampleID] == nil { tracks[track.sampleID] = index + 1 }
        if tracks != drumTracks { drumTracks = tracks }
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
            if !pattern.addTrack(sampleID: id, label: sample.effectiveCategory ?? "Sample", category: sample.effectiveCategory, preset: drumPreset) { skipped += 1 }
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
            pattern.addTrack(sampleID: pick.id, label: slot.category, category: slot.category, alternatives: slot.candidates, preset: drumPreset)
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
        guard let sample = sampleByID[id] else { return }
        drumPattern.replaceSample(track: index, with: id)
        // The track is named after the new sound's category (when it has one).
        if let category = sample.effectiveCategory { drumPattern.tracks[index].label = category }
        if !drumPattern.tracks[index].alternatives.isEmpty, !drumPattern.tracks[index].alternatives.contains(id) {
            drumPattern.tracks[index].alternatives.append(id)
        }
    }

    /// Library samples for dropped files, in drop order. Files are matched by path; a drag that started in this
    /// app may arrive as a copy at another path, so those are matched by file name against what was just dragged.
    func librarySamples(forFiles urls: [URL]) -> [SampleRecord] {
        // The drop carried no readable file (it can happen for a drag that began in this window): use what was just dragged.
        if urls.isEmpty {
            guard Date().timeIntervalSince(recentDragAt) < 60, let id = recentDrags.last, let sample = sampleByID[id] else { return [] }
            return [sample]
        }
        let byPath = Dictionary((samples + usbSamples).map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
        let dragged = recentDrags.reversed().compactMap { sampleByID[$0] }
        var result: [SampleRecord] = []
        for url in urls {
            let match = byPath[url.standardizedFileURL.path]
                ?? dragged.first { $0.url.lastPathComponent == url.lastPathComponent }
            if let match, !result.contains(where: { $0.id == match.id }) { result.append(match) }
        }
        return result
    }

    /// A sample dragged onto a track replaces its sound (and is previewed).
    func dropOnDrumTrack(_ index: Int, files urls: [URL]) {
        guard let sample = librarySamples(forFiles: urls).first else { return }
        replaceDrumSample(track: index, with: sample.id)
        select(sample.id, play: true)
    }

    /// Samples dragged onto the empty part of the drawer become new tracks.
    func dropOnDrums(files urls: [URL]) {
        addToDrums(librarySamples(forFiles: urls).map(\.id))
    }

    func drumSampleName(_ track: DrumTrack) -> String {
        guard let sample = sampleByID[track.sampleID] else { return "Missing sample" }
        return activeTrim(for: sample) == nil ? sample.name : sample.name + " · trimmed"
    }

    // MARK: dropping files on the window

    /// Which drop place is under a point (window coordinates). Tracks win over the drawer around them.
    func dropZone(at point: CGPoint) -> DropZone? {
        let tracks = dropZones.filter { if case .drumTrack = $0.key { return true } else { return false } }
        return tracks.first { $0.value.contains(point) }?.key ?? (dropZones[.drums]?.contains(point) == true ? .drums : nil)
    }

    func handleDrop(_ urls: [URL], on zone: DropZone?) {
        switch zone {
        case .drumTrack(let index): dropOnDrumTrack(index, files: urls)
        case .drums: dropOnDrums(files: urls)
        case nil:
            // Anywhere else, an audio file finds similar sounds.
            if let file = urls.first(where: { FolderScanner.isSupported($0) }) { findSimilar(toFileAt: file) }
        }
    }
}
