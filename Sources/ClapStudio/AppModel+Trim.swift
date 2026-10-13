import AppKit
import ClapCore
import Foundation

/// Non-destructive trims. The audio file is never changed; the trim decides what plays in the drum machine
/// and previews, and what is written when exporting.
extension AppModel {
    /// The trim that applies to a sample, fitted to the file's length (nil when none or it no longer fits).
    func activeTrim(for sample: SampleRecord) -> SampleTrim? {
        trims[sample.id]?.clamped(toDuration: sample.duration)
    }

    /// What the sample cuts out of its file (nil when it only has edits, or nothing at all).
    var selectedTrim: SampleTrim? {
        guard let sample = selectedSample, let trim = activeTrim(for: sample), !trim.coversWholeFile(duration: sample.duration) else { return nil }
        return trim
    }

    /// Saves a trim for a sample (nil removes it) and makes it undoable.
    func setTrim(_ trim: SampleTrim?, for id: Int64, actionName: String = "Trim") {
        // A trim that cuts nothing and changes nothing is no trim.
        var trim = trim
        if let t = trim, t.edit.isNeutral, let sample = sampleByID[id], t.coversWholeFile(duration: sample.duration) { trim = nil }
        guard trims[id] != trim else { return }
        let before = trims[id]
        apply(trim, for: id)
        record(LibraryEdit(name: actionName, undo: { [weak self] in self?.apply(before, for: id) },
                           redo: { [weak self] in self?.apply(trim, for: id) }))
    }

    private func apply(_ trim: SampleTrim?, for id: Int64) {
        do { try store?.setTrim(trim, sampleID: id) } catch { errorMessage = "Could not save the trim: \(error)"; return }
        trims[id] = trim
        if drumPattern.tracks.contains(where: { $0.sampleID == id }) { pushDrumPattern() }
    }

    /// Moves the start of the selected sample's trim (creating one that runs to the end of the file if needed).
    func setTrimStart(atSeconds seconds: Double) {
        guard let sample = selectedSample, sample.duration > 0 else { return }
        let current = selectedTrim ?? SampleTrim(start: 0, end: sample.duration)
        let start = min(max(0, seconds), current.end - SampleTrim.minimumLength)
        setTrim(SampleTrim(start: start, end: current.end, fadeOut: current.fadeOut, edit: selectedEdit), for: sample.id)
    }

    /// Moves the end of the selected sample's trim (creating one that starts at the beginning if needed).
    func setTrimEnd(atSeconds seconds: Double) {
        guard let sample = selectedSample, sample.duration > 0 else { return }
        let current = selectedTrim ?? SampleTrim(start: 0, end: sample.duration)
        let end = max(min(sample.duration, seconds), current.start + SampleTrim.minimumLength)
        setTrim(SampleTrim(start: current.start, end: end, fadeOut: current.fadeOut, edit: selectedEdit), for: sample.id)
    }

    func setTrimFadeOut(_ seconds: Double) {
        guard let sample = selectedSample, let current = selectedTrim else { return }
        setTrim(SampleTrim(start: current.start, end: current.end, fadeOut: seconds, edit: selectedEdit), for: sample.id)
    }

    /// Takes the cut away; the sound edits stay.
    func clearTrim() {
        guard let sample = selectedSample else { return }
        setTrim(SampleTrim(start: 0, end: sample.duration, edit: selectedEdit), for: sample.id, actionName: "Remove Trim")
    }

    /// Where the user is pointing: the spot they clicked on the waveform, or else the playhead.
    var trimPointSeconds: Double? { startMarkerSeconds ?? playback.playhead() }

    // MARK: playback

    func playTrim() {
        guard let sample = selectedSample, let trim = selectedTrim else { return }
        playRegion(of: sample, start: trim.start, end: trim.end, fadeOut: trim.effectiveFadeOut)
    }

    /// Plays from `seconds` through the sample's end, reading from disk. Used for the trimmed part, and for spots
    /// beyond what the preview cache holds in very long files.
    func playRegion(of sample: SampleRecord, start: Double, end: Double?, fadeOut: Double = SampleTrim.declick) {
        guard FileManager.default.isReadableFile(atPath: sample.url.path) else {
            errorMessage = "\(sample.name) is not available (is the volume mounted?)"
            return
        }
        let fit = adjustment(for: sample)
        player.playRegion(sampleID: sample.id, url: sample.url, start: start, end: end, fadeOut: fadeOut,
                          edit: activeTrim(for: sample)?.edit, rate: fit.rate,
                          pitchCents: Float(fit.semitones * 100), gainDB: previewGain(for: sample)) { [weak self] error in
            if let error { Task { @MainActor in self?.errorMessage = "Cannot play \(sample.name): \(error.localizedDescription)" } }
        }
    }

    // MARK: export

    /// The samples the export sheet acts on.
    var exportSamples: [SampleRecord] { (exportIDs ?? []).compactMap { sampleByID[$0] } }

    func exportTrimmed(_ id: Int64) { openExport(ids: [id]) }

    func openExport(ids: [Int64]) {
        exportIDs = ids
        showExport = true
    }
}
