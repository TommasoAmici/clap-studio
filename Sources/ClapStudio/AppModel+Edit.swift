import ClapCore
import Foundation

/// Non-destructive sound edits (reverse, speed, filters, volume). They live with the trim, so the drum machine,
/// previews and exports all use them, and the audio file is never changed.
extension AppModel {
    var selectedEdit: SampleEdit { selectedSample.flatMap(activeTrim(for:))?.edit ?? SampleEdit() }

    /// Sets the selected sample's edit (one undo step) and plays the result.
    func setEdit(_ edit: SampleEdit, audition: Bool = true) {
        guard let sample = selectedSample, sample.duration > 0 else { return }
        let edit = edit.clamped()
        let current = selectedTrim ?? SampleTrim(start: 0, end: sample.duration)
        guard edit != selectedEdit else { return }
        setTrim(SampleTrim(start: current.start, end: current.end, fadeOut: current.fadeOut, edit: edit), for: sample.id, actionName: "Edit Sound")
        if audition { playSample(sample) }
    }

    func resetEdit() { setEdit(SampleEdit(), audition: false) }
}
