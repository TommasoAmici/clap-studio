import ClapCore
import Foundation

/// The project's tempo and key, so loops and tonal sounds can be auditioned in context.
extension AppModel {
    private enum Keys {
        static let bpm = "project.bpm", tonic = "project.tonic", matchTempo = "project.matchTempo", matchKey = "project.matchKey"
    }

    func loadProjectSettings() {
        let d = UserDefaults.standard
        let bpm = d.double(forKey: Keys.bpm)
        project = ProjectSettings(bpm: bpm > 0 ? bpm : nil, tonic: d.string(forKey: Keys.tonic),
                                  matchTempo: d.bool(forKey: Keys.matchTempo), matchKey: d.bool(forKey: Keys.matchKey))
    }

    func saveProjectSettings() {
        let d = UserDefaults.standard
        d.set(project.bpm ?? 0, forKey: Keys.bpm)
        d.set(project.tonic, forKey: Keys.tonic)
        d.set(project.matchTempo, forKey: Keys.matchTempo)
        d.set(project.matchKey, forKey: Keys.matchKey)
    }

    /// How a sample will be bent when played in the project (rate 1 and 0 semitones when nothing applies).
    func adjustment(for sample: SampleRecord) -> PlaybackAdjustment {
        var adjustment = PlaybackAdjustment()
        if project.matchTempo, sample.isLoop == true {
            adjustment.rate = TempoSync.rate(sampleBPM: sample.effectiveBPM, projectBPM: project.bpm)
        }
        if project.matchKey { adjustment.semitones = TempoSync.semitones(sampleKey: sample.keyName, projectTonic: project.tonic) }
        return adjustment
    }

    /// Takes the tempo of the selected loop as the project's.
    func useSelectedTempoForProject() {
        guard let bpm = selectedSample?.effectiveBPM else { return }
        project.bpm = (bpm * 10).rounded() / 10
    }
}

struct ProjectSettings: Equatable {
    var bpm: Double?
    var tonic: String?
    var matchTempo = false
    var matchKey = false
}

struct PlaybackAdjustment: Equatable {
    var rate: Float = 1
    var semitones = 0
    var isNeutral: Bool { rate == 1 && semitones == 0 }
}
