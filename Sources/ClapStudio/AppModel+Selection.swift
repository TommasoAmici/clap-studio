import ClapCore
import Foundation

extension AppModel {
    // MARK: selection and similarity

    func select(_ id: Int64?, play: Bool = false) {
        guard id != selectedID || play else { return }
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
        player.play(sampleID: sample.id, url: sample.url, startSeconds: seconds) { [weak self] error in
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

    // MARK: cues

    private var nativeRate: Double { (selectedSample?.sampleRate ?? 0) > 0 ? selectedSample!.sampleRate : 44_100 }

    var selectedDuration: Double {
        if let d = selectedSample?.duration, d > 0 { return d }
        return playback.sampleID == selectedID ? playback.duration : 0
    }

    func reloadCues() {
        guard let store, let id = selectedID else { cues = []; return }
        cues = store.cues(sampleID: id)
        cuesDirty = store.cuesDirty(sampleID: id)
        mutate(id) { $0.cueCount = self.cues.count }
    }

    func addCue(atSeconds seconds: Double) {
        addCue(atFrame: Int64((seconds * nativeRate).rounded()))
    }

    func addCue(atFrame frame: Int64) {
        guard let id = selectedID, let editor = cueEditor else { return }
        run { let cue = try editor.add(sampleID: id, frame: frame); self.selectedCueID = cue.id }
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
        run { try editor.move(id: id, to: Int64(max(0, seconds) * self.nativeRate)) }
    }

    func renameCue(_ id: Int64, to label: String) {
        guard let editor = cueEditor else { return }
        run { try editor.rename(id: id, to: label) }
    }

    func removeCue(_ id: Int64) {
        guard let editor = cueEditor else { return }
        run { try editor.remove(id: id); if self.selectedCueID == id { self.selectedCueID = nil } }
    }

    func undoCue() { guard let editor = cueEditor else { return }; run { try editor.undo() } }
    func redoCue() { guard let editor = cueEditor else { return }; run { try editor.redo() } }

    func playCue(_ cue: CuePoint) {
        selectedCueID = cue.id
        if let s = selectedSample { playSample(s, from: Double(cue.positionFrames) / nativeRate) }
    }

    func playCue(number: Int) {
        guard number >= 1, number <= cues.count else { return }
        playCue(cues[number - 1])
    }

    func seconds(for cue: CuePoint) -> Double { Double(cue.positionFrames) / nativeRate }

    /// Explicit, confirmed action: embeds the app's cues into the WAV file.
    func writeCuesToFile(keepBackup: Bool) {
        guard let store, let sample = selectedSample else { return }
        do {
            try store.writeCuesToFile(sample: sample, keepBackup: keepBackup)
            if let refreshed = store.loadSamples().first(where: { $0.id == sample.id }) {
                mutate(sample.id) { $0.size = refreshed.size; $0.mtime = refreshed.mtime }
            }
            reloadCues()
        } catch { errorMessage = String(describing: error) }
    }

    func reloadCuesFromFile() {
        guard let store, let sample = selectedSample else { return }
        do { try store.reloadCuesFromFile(sample: sample); reloadCues() } catch { errorMessage = String(describing: error) }
    }

    var canWriteCuesToFile: Bool {
        guard let ext = selectedSample?.ext else { return false }
        return ext == "wav" || ext == "wave"
    }

    private func run(_ body: () throws -> Void) {
        do { try body(); reloadCues() } catch { errorMessage = String(describing: error) }
    }
}
