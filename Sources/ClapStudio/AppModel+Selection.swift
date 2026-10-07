import ClapCore
import Foundation

extension AppModel {
    // MARK: selection and similarity

    func select(_ id: Int64?, play: Bool = false, keepSweep: Bool = false) {
        guard id != selectedID || play else { return }
        if !keepSweep { sweepList = [] }
        if id != selectedID { startMarkerFrame = nil }
        selectedID = id
        selectedCueID = nil
        guard let id, let sample = sampleByID[id] else {
            similar = []; similarRows = []; cues = []; waveform = []
            return
        }
        reloadCues()
        updateSimilar(for: id)
        loadWaveform(sample)
        if play && autoplay { playSample(sample) }
    }

    func updateSimilar(for id: Int64) {
        guard let snap = snapshot, let row = snap.index.row(forID: id) else { similar = []; similarRows = []; return }
        let neighbors = snap.index.similar(toRow: row, limit: 50)
        similarRows = neighbors.map(\.row)
        similar = neighbors.compactMap { n in
            sampleByID[snap.index.ids[n.row]].map { SimilarResult(sample: $0, score: n.score) }
        }
    }

    func showSimilar(to id: Int64) {
        smartFilter = .all
        folderSelection = nil
        select(id)
    }

    private func loadWaveform(_ sample: SampleRecord) {
        waveform = []
        let player = self.player
        Task {
            let peaks = await Task.detached { () -> [Float] in
                guard let buffer = try? player.cache.buffer(for: sample.url) else { return [] }
                return AudioBufferCache.peaks(of: buffer, bins: 800)
            }.value
            if selectedID == sample.id { waveform = peaks }
        }
    }

    // MARK: playback

    func playSample(_ sample: SampleRecord, from seconds: Double = 0) {
        guard FileManager.default.isReadableFile(atPath: sample.url.path) else {
            errorMessage = "\(sample.name) is not available (is the volume mounted?)"
            return
        }
        let fit = adjustment(for: sample)
        player.play(sampleID: sample.id, url: sample.url, startSeconds: seconds, rate: fit.rate,
                    pitchCents: Float(fit.semitones * 100)) { [weak self] error in
            if let error { Task { @MainActor in self?.errorMessage = "Cannot play \(sample.name): \(error.localizedDescription)" } }
        }
    }

    func togglePlayback() {
        if playback.sampleID != nil { player.stop(); return }
        if let s = selectedSample { playSample(s, from: startMarkerSeconds ?? 0) }
    }

    /// Hover preview from the map; returns quickly and supersedes any decode in flight.
    func previewRow(_ row: Int?) {
        hoverRow = row
        guard hoverPlay, let row, let snap = snapshot, let s = sampleByID[snap.index.ids[row]] else { return }
        playSample(s)
    }

    // MARK: usage

    /// Called when the user starts dragging a sample out of the app.
    func registerGrab(_ id: Int64) {
        let now = Date()
        if let last = lastGrab[id], now.timeIntervalSince(last) < 1 { return }   // one drag, one count
        lastGrab[id] = now
        guard let store else { return }
        do { try store.recordGrab(sampleID: id, at: now) } catch { errorMessage = "Could not record usage: \(error)"; return }
        mutate(id) { $0.useCount += 1; $0.lastUsed = now.timeIntervalSince1970 }
        if smartFilter != .all { refilter() }
    }

    func mutate(_ id: Int64, _ change: (inout SampleRecord) -> Void) {
        if var s = sampleByID[id] { change(&s); sampleByID[id] = s }
        if let i = samples.firstIndex(where: { $0.id == id }) { change(&samples[i]) }
        if let i = visible.firstIndex(where: { $0.id == id }) { change(&visible[i]) }
    }

    // MARK: properties

    /// Sets (or with nil clears) the user's BPM for a loop; the detected value is kept.
    func setBPM(_ id: Int64, _ bpm: Double?) {
        guard let store else { return }
        do { try store.setManualBPM(sampleID: id, bpm) } catch { errorMessage = "Could not save the tempo: \(error)"; return }
        mutate(id) { $0.bpmManual = bpm }
        if descriptorFilter.isActive { refilter() }
    }

    /// Sets (or with nil clears) the user's category; the automatic one is kept.
    func setCategory(_ id: Int64, _ category: String?) {
        guard let store else { return }
        do { try store.setManualCategory(sampleID: id, category) } catch { errorMessage = "Could not save the category: \(error)"; return }
        mutate(id) { $0.categoryManual = category }
        updateCategoryCounts()
        if descriptorFilter.isActive { refilter() }
    }

    // MARK: cues

    private var nativeRate: Double { (selectedSample?.sampleRate ?? 0) > 0 ? selectedSample!.sampleRate : 44_100 }

    var selectedDuration: Double {
        if let d = selectedSample?.duration, d > 0 { return d }
        return playback.sampleID == selectedID ? playback.duration : 0
    }

    func reloadCues() {
        guard let store, let id = selectedID else { cues = []; return }
        cues = store.cues(sampleID: id)
        mutate(id) { $0.cueCount = self.cues.count }
    }

    func addCue(atSeconds seconds: Double) {
        addCue(atFrame: Int64((seconds * nativeRate).rounded()))
    }

    func addCue(atFrame frame: Int64) {
        guard let id = selectedID, let editor = cueEditor else { return }
        editSelected { let cue = try editor.add(sampleID: id, frame: frame); self.selectedCueID = cue.id }
    }

    func addCueAtPlayhead() { addCue(atSeconds: playback.playhead() ?? 0) }

    /// Click on the waveform: remember that exact frame and audition from it.
    func placeStartMarker(atSeconds seconds: Double) {
        startMarkerFrame = Int64((max(0, seconds) * nativeRate).rounded())
        if let s = selectedSample { playSample(s, from: seconds) }
    }

    var startMarkerSeconds: Double? { startMarkerFrame.map { Double($0) / nativeRate } }

    /// Sets a cue where the user originally clicked (not where playback has reached). Without a
    /// marker it falls back to the playhead.
    func addCueAtMarker() {
        guard let frame = startMarkerFrame else { addCueAtPlayhead(); return }
        addCue(atFrame: frame)
        startMarkerFrame = nil      // the cue now marks the spot
    }

    func moveCue(_ id: Int64, toSeconds seconds: Double) {
        guard let editor = cueEditor else { return }
        editSelected { try editor.move(id: id, to: Int64(max(0, seconds) * self.nativeRate)) }
    }

    func renameCue(_ id: Int64, to label: String) {
        guard let editor = cueEditor else { return }
        editSelected { try editor.rename(id: id, to: label) }
    }

    func removeCue(_ id: Int64) {
        guard let editor = cueEditor else { return }
        editSelected { try editor.remove(id: id); if self.selectedCueID == id { self.selectedCueID = nil } }
    }

    func undoCue() { guard let editor = cueEditor else { return }; run(affecting: { try editor.undo() }) }
    func redoCue() { guard let editor = cueEditor else { return }; run(affecting: { try editor.redo() }) }

    func playCue(_ cue: CuePoint) {
        selectedCueID = cue.id
        if let s = selectedSample { playSample(s, from: Double(cue.positionFrames) / nativeRate) }
    }

    func playCue(number: Int) {
        guard number >= 1, number <= cues.count else { return }
        playCue(cues[number - 1])
    }

    func seconds(for cue: CuePoint) -> Double { Double(cue.positionFrames) / nativeRate }

    /// Why the selected sample's cues are not (or not yet) stored in its file, if they are not.
    var cueFileNote: String? {
        guard let sample = selectedSample else { return nil }
        if let problem = cueSyncIssues[sample.id] { return "Could not save cues into the file (\(problem)). They are kept in Clap Studio." }
        if !cues.isEmpty && !CueFileSync.canStoreCues(ext: sample.ext) {
            return "Only WAV files can hold cues, so these stay in Clap Studio."
        }
        return nil
    }

    func handleCueSync(_ outcome: CueFileSync.Outcome) {
        switch outcome {
        case .written(let id):
            cueSyncIssues[id] = nil
            if let fresh = store?.sample(id: id) { mutate(id) { $0.size = fresh.size; $0.mtime = fresh.mtime } }
        case .appOnly(let id): cueSyncIssues[id] = nil
        case .failed(let id, let message): cueSyncIssues[id] = message
        }
    }

    /// Runs a cue edit on the selected sample, refreshes the list and schedules the file update.
    private func editSelected(_ body: () throws -> Void) {
        run(affecting: { try body(); return self.selectedID })
    }

    /// `body` returns the id of the sample it changed (undo/redo may touch one that is no longer selected).
    private func run(affecting body: () throws -> Int64?) {
        do {
            let changed = try body()
            reloadCues()
            if let changed { cueSync?.markChanged(sampleID: changed) }
        } catch { errorMessage = String(describing: error) }
    }
}
