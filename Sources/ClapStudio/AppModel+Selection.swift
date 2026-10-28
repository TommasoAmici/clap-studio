import ClapCore
import Foundation

extension AppModel {
    // MARK: selection and similarity

    /// `keepSelection` leaves the highlighted rows as they are (a sample picked while several are selected is
    /// shown and heard, but the rest stay selected for a batch action).
    func select(_ id: Int64?, play: Bool = false, keepSweep: Bool = false, keepSelection: Bool = false) {
        guard id != selectedID || play else { return }
        if !keepSweep { sweepList = [] }
        if id != selectedID { startMarkerFrame = nil }
        selectedID = id
        // A search that found a spot inside a field recording starts there, unless the user picked a spot.
        let found = id.flatMap { segmentMatches[$0] }
        if let id, let found, startMarkerFrame == nil, let sample = sampleByID[id] {
            startMarkerFrame = Int64((found.start * (sample.sampleRate > 0 ? sample.sampleRate : 44_100)).rounded())
        }
        if !keepSelection, tableSelection != (id.map { [$0] } ?? []) { tableSelection = id.map { [$0] } ?? [] }
        selectedCueID = nil
        guard let id, let sample = sampleByID[id] else {
            similar = []; similarRows = []; cues = []; waveform = []
            return
        }
        reloadCues()
        updateSimilar(for: id)
        loadWaveform(sample)
        if play && autoplay { playSample(sample, from: found?.start ?? 0) }
    }

    /// What a command acts on: every highlighted row, or just the selected sample.
    var actionTargets: [Int64] {
        if tableSelection.count > 1 { return Array(tableSelection) }
        return selectedID.map { [$0] } ?? []
    }

    func updateSimilar(for id: Int64) {
        guard let snap = snapshot, let reference = sampleByID[id] else { similar = []; similarRows = []; return }
        let neighbors = AspectSimilarity.rank(reference: reference, index: snap.index, weights: aspectWeights, limit: 50) { [sampleByID] in sampleByID[$0] }
        similarRows = neighbors.map(\.row)
        similar = neighbors.compactMap { n in
            sampleByID[snap.index.ids[n.row]].map { SimilarResult(sample: $0, score: n.score) }
        }
    }

    /// Narrows whatever view is open (the list, or the map) to the sounds closest to a sample, nearest first.
    /// The tab is left as it is; the banner above them clears it again.
    func showSimilar(to id: Int64) {
        guard let snap = snapshot, let reference = sampleByID[id] else {
            errorMessage = "Finding similar sounds needs the library to be indexed and analysed."
            return
        }
        let keptWords = exampleQuery?.referenceID == id ? exampleQuery?.refinement ?? "" : ""
        selectSidebar("smart.\(SmartFilter.all.rawValue)")
        searchText = ""
        let neighbours = AspectSimilarity.rank(reference: reference, index: snap.index, weights: aspectWeights, limit: 100) { [sampleByID] in sampleByID[$0] }
        var scores = Dictionary(neighbours.map { (snap.index.ids[$0.row], $0.score) }, uniquingKeysWith: max)
        scores[id] = (scores.values.max() ?? 1) + 1       // the sample itself leads
        exampleQuery = ExampleQuery(name: reference.name, scores: scores, referenceID: id)
        refilter()
        select(id)
        addSegmentMatches(reference: reference)
        if !keptWords.isEmpty { exampleQuery?.refinement = keptWords; scheduleRefinement(immediately: true) }
    }

    /// Field recordings are found by their best segment, which the map's reduced vectors cannot see. Added once
    /// the segments are loaded; recordings that would not make the list of neighbours stay out.
    private func addSegmentMatches(reference: SampleRecord) {
        guard let store else { return }
        let id = reference.id, cache = segmentCache
        Task {
            let matches = await Task.detached { () -> [Int64: SegmentMatch] in
                guard let embedding = try? store.embeddings(ids: [id]), embedding.dim > 0,
                      let index = try? cache.index(store: store, modelVersion: ClapEmbedder.versionTag) else { return [:] }
                return index.bestMatches(query: embedding.flat, excluding: id)
            }.value
            guard !matches.isEmpty, var query = exampleQuery, query.referenceID == id else { return }
            let cutoff = query.scores.count >= 100 ? (query.scores.values.min() ?? -.infinity) : -.infinity
            for (other, match) in matches {
                guard let sample = sampleByID[other] else { continue }
                let score = AspectSimilarity.score(cosine: match.score, reference: reference, other: sample, weights: aspectWeights)
                query.segments[other] = match
                if score >= cutoff { query.scores[other] = max(query.scores[other] ?? -.infinity, score) }
            }
            exampleQuery = query
            refilter()
        }
    }

    /// Where the current search matched inside each field recording (empty for ordinary searches).
    var segmentMatches: [Int64: SegmentMatch] {
        if let example = exampleQuery { return example.segments }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return soundSearchActive && soundScoresQuery == query ? soundSegments : [:]
    }

    private func loadWaveform(_ sample: SampleRecord) {
        waveform = []
        Task {
            let peaks = await Task.detached { () -> [Float] in
                // The whole file, however long (the preview cache only holds the first two minutes).
                (try? WaveformPeaks.compute(url: sample.url, bins: 800)) ?? []
            }.value
            if selectedID == sample.id { waveform = peaks }
        }
    }

    // MARK: playback

    /// Plays a sample. A trimmed sample plays just its trimmed part, unless it is started from a spot
    /// the user picked (clicking the waveform, a cue) or `fullFile` is set. Spots beyond what the preview
    /// cache holds in very long files are read from disk.
    func playSample(_ sample: SampleRecord, from seconds: Double = 0, fullFile: Bool = false) {
        if usesEffects {
            let trim: SampleTrim?
            if seconds == 0, !fullFile { trim = activeTrim(for: sample) }
            else if seconds > 0 || (!fullFile && activeTrim(for: sample)?.edit.isNeutral == false) {
                trim = SampleTrim(start: seconds, end: sample.duration, edit: fullFile ? SampleEdit() : activeTrim(for: sample)?.edit ?? SampleEdit())
            } else { trim = nil }
            auditionEffects(sample, trim: trim)
            return
        }
        effects.stopPreview()
        if seconds == 0, !fullFile, let trim = activeTrim(for: sample) {
            playRegion(of: sample, start: trim.start, end: trim.end, fadeOut: trim.effectiveFadeOut)
            return
        }
        // An edited sound is always heard edited, from wherever it is started.
        if !fullFile, let trim = activeTrim(for: sample), !trim.edit.isNeutral {
            playRegion(of: sample, start: seconds, end: nil)
            return
        }
        if seconds >= AudioBufferCache.maxSeconds - 1 {
            playRegion(of: sample, start: seconds, end: nil)
            return
        }
        guard FileManager.default.isReadableFile(atPath: sample.url.path) else {
            errorMessage = "\(sample.name) is not available (is the volume mounted?)"
            return
        }
        let fit = adjustment(for: sample)
        player.play(sampleID: sample.id, url: sample.url, startSeconds: seconds, rate: fit.rate,
                    pitchCents: Float(fit.semitones * 100), gainDB: previewGain(for: sample)) { [weak self] error in
            if let error { Task { @MainActor in self?.errorMessage = "Cannot play \(sample.name): \(error.localizedDescription)" } }
        }
    }

    func togglePlayback() {
        if playback.sampleID != nil { stopAudition(); return }
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
        recentDragAt = Date()
        recentDrags.removeAll { $0 == id }
        recentDrags.append(id)
        if recentDrags.count > 64 { recentDrags.removeFirst(recentDrags.count - 64) }
        let now = Date()
        if let last = lastGrab[id], now.timeIntervalSince(last) < 1 { return }   // one drag, one count
        lastGrab[id] = now
        guard let store else { return }
        do { try store.recordGrab(sampleID: id, at: now) } catch { errorMessage = "Could not record usage: \(error)"; return }
        mutate(id) { $0.useCount += 1; $0.lastUsed = now.timeIntervalSince1970 }
        if mapColorMode == .usage { refreshMapColoring() }
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

    /// A file put in the Field recording category by hand is segmented and listened to like a long one; one taken out of it
    /// is indexed as a single sound again. Both need the file read again, which the index run does.
    private func resegmentIfFieldRecordingChanged() {
        guard let store, let queued = try? store.markFieldRecordingsStale(), queued > 0 else { return }
        requestIndexing()
    }

    /// Sets (or with nil clears) the user's category; the automatic one is kept.
    func setCategory(_ id: Int64, _ category: String?) {
        guard let store else { return }
        do { try store.setManualCategory(sampleID: id, category) } catch { errorMessage = "Could not save the category: \(error)"; return }
        mutate(id) { $0.categoryManual = category }
        resegmentIfFieldRecordingChanged()
        updateCategoryCounts()
        buildClusterInfo()
        if mapColorMode == .category { refreshMapColoring() }
        if descriptorFilter.isActive { refilter() }
    }

    /// Sets (or with nil clears) the category of several samples at once, as one undoable change.
    func setCategory(_ ids: [Int64], _ category: String?) {
        let before = ids.compactMap { id in sampleByID[id].map { (id: id, category: $0.categoryManual) } }
        let changed = before.filter { $0.category != category }
        guard !changed.isEmpty else { return }
        let after = changed.map { (id: $0.id, category: category) }
        let name = category.map { "Set Category to \($0) for \(samplesPhrase(changed.count))" }
            ?? "Use Automatic Category for \(samplesPhrase(changed.count))"
        record(LibraryEdit(name: name,
                           undo: { [unowned self] in applyCategories(changed) },
                           redo: { [unowned self] in applyCategories(after) }))
        applyCategories(after)
    }

    private func applyCategories(_ values: [(id: Int64, category: String?)]) {
        guard let store, !values.isEmpty else { return }
        do { try store.setManualCategories(values) } catch { errorMessage = "Could not save the categories: \(error)"; return }
        for value in values { mutate(value.id) { $0.categoryManual = value.category } }
        resegmentIfFieldRecordingChanged()
        updateCategoryCounts()
        buildClusterInfo()
        if mapColorMode == .category { refreshMapColoring() }
        if descriptorFilter.isActive { refilter() }
    }

    /// Changes the moods of several samples at once as one undoable change. `change` maps a sample's current moods
    /// to its new ones (nil: back to the automatic moods).
    func changeMoods(_ ids: [Int64], named name: String, _ change: ([String]) -> [String]?) {
        let before = ids.compactMap { id in sampleByID[id].map { (id: id, moods: $0.moodsManual) } }
        let after = ids.compactMap { id -> (id: Int64, moods: [String]?)? in
            guard let s = sampleByID[id] else { return nil }
            return (id, change(s.moods).map { SoundMoods.sorted($0) })
        }
        let changed = zip(before, after).filter { $0.moods != $1.moods }
        guard !changed.isEmpty else { return }
        let oldValues = changed.map(\.0), newValues = changed.map(\.1)
        record(LibraryEdit(name: "\(name) for \(samplesPhrase(changed.count))",
                           undo: { [unowned self] in applyMoods(oldValues) },
                           redo: { [unowned self] in applyMoods(newValues) }))
        applyMoods(newValues)
    }

    private func applyMoods(_ values: [(id: Int64, moods: [String]?)]) {
        guard let store, !values.isEmpty else { return }
        do { try store.setManualMoods(values) } catch { errorMessage = "Could not save the moods: \(error)"; return }
        for value in values {
            mutate(value.id) { $0.moodsManual = value.moods; $0.moods = value.moods ?? $0.moodsAuto }
        }
        updateMoodCounts()
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
        if isOnUsb(sample.id) && !cues.isEmpty { return "Files on a USB drive are never changed, so these cues stay in Clap Studio." }
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
            if let changed, !isOnUsb(changed) { cueSync?.markChanged(sampleID: changed) }
        } catch { errorMessage = String(describing: error) }
    }
}

extension AppModel {
    /// How many segments a field recording was split into.
    func segmentCount(_ id: Int64) -> Int { store?.segmentCount(sampleID: id) ?? 0 }

    /// The sounds heard in a field recording and where, longest first.
    func soundOccurrences(_ id: Int64) -> [SoundOccurrence] { store?.soundOccurrences(sampleID: id) ?? [] }
}
