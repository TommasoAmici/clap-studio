import ClapCore
import Foundation

/// A small step sequencer for trying samples together. It follows the project tempo and takes its sounds from
/// the selection or the kit builder.
extension AppModel {
    /// Tempo the drum machine plays at: the project's, or a neutral 120 when none is set.
    var drumTempo: Double { project.bpm ?? DrumTiming.defaultBPM }

    var drumPreset: DrumPreset? { DrumPreset.preset(id: drumPresetID, among: userDrumPresets) }

    private static let drumPresetKey = "drum.preset", userDrumPresetsKey = "drum.userPresets"

    func loadDrumGrooves() {
        let d = UserDefaults.standard
        let savedID = d.string(forKey: Self.drumPresetKey)     // read first: assigning the grooves below stores the (still empty) choice
        if let data = d.data(forKey: Self.userDrumPresetsKey), let saved = try? JSONDecoder().decode([DrumPreset].self, from: data) {
            userDrumPresets = saved.compactMap { preset in
                guard let name = DrumPreset.cleanName(preset.name) else { return nil }
                guard preset.id.hasPrefix("user.") else { return nil }
                var copy = preset; copy.isUser = true; copy.name = name
                return copy
            }
        }
        // An id that no longer exists (a deleted groove) is dropped.
        drumPresetID = DrumPreset.preset(id: savedID, among: userDrumPresets)?.id
    }

    func storeDrumGrooves() {
        let d = UserDefaults.standard
        if let drumPresetID { d.set(drumPresetID, forKey: Self.drumPresetKey) } else { d.removeObject(forKey: Self.drumPresetKey) }
        if userDrumPresets.isEmpty { d.removeObject(forKey: Self.userDrumPresetsKey) }
        else if let data = try? JSONEncoder().encode(userDrumPresets) { d.set(data, forKey: Self.userDrumPresetsKey) }
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

    /// Saves the pattern on screen, with the project tempo and its swing, as a groove of the user's own and selects
    /// it. A groove saved under the same name is replaced.
    func saveDrumPreset(named rawName: String) {
        guard let name = DrumPreset.cleanName(rawName) else { return }
        let existing = userDrumPresets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard let preset = drumPattern.makePreset(name: name, id: existing?.id ?? "user." + UUID().uuidString, bpm: drumTempo) else {
            errorMessage = "Turn on some steps before saving a groove."
            return
        }
        if let existing, let index = userDrumPresets.firstIndex(of: existing) { userDrumPresets[index] = preset } else { userDrumPresets.append(preset) }
        drumPresetID = preset.id
    }

    func deleteDrumPreset(_ id: String) {
        userDrumPresets.removeAll { $0.id == id }
        if drumPresetID == id { drumPresetID = nil }
    }

    // MARK: remembering the pattern

    private static let drumPatternKey = "drum.pattern", drumOpenKey = "drum.open"
    private static let drumWriter = DispatchQueue(label: "clap.drums.save", qos: .utility)

    /// Brings back the pattern (sounds, steps, mix, swing) and whether the drawer was open. Run before the library is
    /// read, so the sounds are matched up later, in `restoreDrumSounds`.
    func loadDrumPattern() {
        let d = UserDefaults.standard
        let wasOpen = d.bool(forKey: Self.drumOpenKey)       // read first: assigning the pattern stores the (still closed) drawer
        if let url = try? DrumStore.defaultURL(), let saved = DrumStore.load(from: url) {
            drumPattern = saved
        } else if let data = d.data(forKey: Self.drumPatternKey), let saved = try? JSONDecoder().decode(DrumPattern.self, from: data) {
            drumPattern = saved.sanitized()
        }
        showDrums = wasOpen && !drumPattern.tracks.isEmpty
    }

    func storeDrumPattern() {
        let d = UserDefaults.standard
        // Sounds read from a USB stick only exist while it is plugged in, so they are not kept.
        var pattern = drumPattern
        pattern.tracks.removeAll { usbSampleIDs.contains($0.sampleID) }
        let saved = pattern
        let legacyKey = Self.drumPatternKey
        Self.drumWriter.async {
            guard let url = try? DrumStore.defaultURL(), (try? DrumStore.save(saved, to: url)) != nil else { return }
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
        d.set(showDrums, forKey: Self.drumOpenKey)
    }

    /// Once the library is loaded, drops saved tracks whose sound is gone and hands the rest to the engine.
    func restoreDrumSounds() {
        guard !drumSourcesReady, !sampleByID.isEmpty else { return }
        drumSourcesReady = true
        guard !drumPattern.tracks.isEmpty else { return }
        var pattern = drumPattern
        pattern.tracks.removeAll { sampleByID[$0.sampleID] == nil }
        if pattern != drumPattern { drumPattern = pattern } else { pushDrumPattern() }
        if pattern.tracks.isEmpty { showDrums = false }
    }

    func makeDrumMachine() -> DrumMachine {
        let machine = DrumMachine(cache: player.cache)
        machine.bpm = drumTempo
        machine.onStep = { [weak self] step in
            MainActor.assumeIsolated { if self?.drumPlaying == true { self?.drumStep = step } }
        }
        machine.onMelodyStep = { [weak self] step in
            MainActor.assumeIsolated { if self?.drumPlaying == true { self?.melodyStep = step } }
        }
        machine.onRunningChange = { [weak self] running in
            MainActor.assumeIsolated {
                self?.drumPlaying = running
                if !running { self?.drumStep = nil; self?.melodyStep = nil }
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
        pushMelodyPattern()
        drumMachine.bpm = drumTempo
        drumMachine.start()
    }

    /// Adds samples as new tracks (up to the track limit, at `index` when given, else at the end), each with a
    /// starter rhythm for its category.
    func addToDrums(_ ids: [Int64], at index: Int? = nil) {
        var pattern = drumPattern
        var skipped = 0
        var position = index
        for id in ids {
            guard let sample = sampleByID[id], !pattern.tracks.contains(where: { $0.sampleID == id }) else { continue }
            if pattern.addTrack(sampleID: id, label: sample.effectiveCategory ?? "Sample", category: sample.effectiveCategory,
                                preset: drumPreset, at: position) {
                position = position.map { $0 + 1 }
            } else { skipped += 1 }
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
        guard let trim = activeTrim(for: sample) else { return sample.name }
        return sample.name + (trim.coversWholeFile(duration: sample.duration) ? " · edited" : " · trimmed")
    }

    // MARK: dropping files on the window

    /// Which drop place is under a point (window coordinates). Over the drum machine the answer is always a track to
    /// swap or a gap to insert into, and the drawer counts a little beyond its edges (above it, and down through the
    /// status bar), so missing the exact spot still lands a new track at the end.
    func dropZone(at point: CGPoint) -> DropZone? {
        // The melody drawer sits right above the drum machine, whose reach extends a little over it: the melody wins there.
        if let tab = dropZones.first(where: { zone, frame in
            if case .melodyTrack = zone { return frame.contains(point) } else { return false }
        }) { return tab.key }
        if let melody = dropZones[.melody], melody.contains(point) { return .melody }
        guard let drawer = dropZones[.drums] else { return nil }
        let reach = CGRect(x: drawer.minX, y: drawer.minY - 28, width: drawer.width, height: drawer.height + 28 + 90)
        guard reach.contains(point) else { return nil }
        let rows = dropZones.compactMap { zone, frame -> (Int, CGRect)? in
            if case .drumTrack(let index) = zone { return (index, frame) } else { return nil }
        }.sorted { $0.0 < $1.0 }
        switch DrumDropTarget.resolve(y: Double(point.y), rows: rows.map { Double($0.1.minY)...Double($0.1.maxY) }) {
        case .replace(let position): return .drumTrack(rows[position].0)
        case .insert(let position): return .drumInsert(position)
        }
    }

    func handleDrop(_ urls: [URL], on zone: DropZone?) {
        switch zone {
        case .drumTrack(let index): dropOnDrumTrack(index, files: urls)
        case .drumInsert(let index): addToDrums(librarySamples(forFiles: urls).map(\.id), at: index)
        case .drums: dropOnDrums(files: urls)
        case .melodyTrack(let index):
            if let midi = urls.first(where: MidiFile.isMidiFile) { importMidi(midi) } else { dropOnMelodyTrack(index, files: urls) }
        case .melody:
            if let midi = urls.first(where: MidiFile.isMidiFile) { importMidi(midi) } else { addToMelody(librarySamples(forFiles: urls).map(\.id)) }
        case nil:
            // Anywhere else, a MIDI file is opened as the melody and an audio file finds similar sounds.
            if let midi = urls.first(where: MidiFile.isMidiFile) { importMidi(midi) }
            else if let file = urls.first(where: { FolderScanner.isSupported($0) }) { findSimilar(toFileAt: file) }
        }
    }
}
