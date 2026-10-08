import ClapCore
import Foundation

/// Sort keys and display strings for the measured properties (missing values sort last when ascending).
extension SampleRecord {
    var bpmSort: Double { effectiveBPM ?? -1 }
    var keySort: String { keyName ?? "" }
    var levelSort: Double { loudnessDB ?? -200 }
    var brightnessSort: Double { centroidHz ?? -1 }
    var categorySort: String { effectiveCategory ?? "" }
    var moodText: String { moods.joined(separator: ", ") }
    var tagsText: String { tags.joined(separator: ", ") }
    var formatText: String { ext.uppercased() }

    var bpmText: String {
        guard let bpm = effectiveBPM else { return "" }
        return String(format: bpm.rounded() == bpm ? "%.0f" : "%.1f", bpm) + (bpmManual != nil ? "*" : "")
    }

    var levelText: String { loudnessDB.map { String(format: "%.1f dB", $0) } ?? "" }

    var brightnessText: String {
        guard let hz = centroidHz, hz > 0 else { return "" }
        return hz >= 1000 ? String(format: "%.1f kHz", hz / 1000) : String(format: "%.0f Hz", hz)
    }

    var typeText: String {
        if isFieldRecording { return "Field recording" }
        return isLoop == true ? "Loop" : (isLoop == false ? "One-shot" : "")
    }
}
