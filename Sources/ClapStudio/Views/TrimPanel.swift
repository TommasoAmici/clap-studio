import ClapCore
import SwiftUI

/// Non-destructive trimming: pick where the sound starts and ends, and use just that part in the drum machine
/// and in exports. The original file is never changed.
struct TrimPanel: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord

    private static let fades: [(title: String, seconds: Double)] = [
        ("Short", 0), ("50 ms", 0.05), ("250 ms", 0.25), ("1 s", 1), ("3 s", 3),
    ]

    var body: some View {
        let trim = model.selectedTrim
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Trim").font(.subheadline.bold())
                Spacer()
                Button("Start Here") { if let t = model.trimPointSeconds { model.setTrimStart(atSeconds: t) } }
                    .help("Start the sound at the spot you clicked on the waveform (or the playhead)")
                Button("End Here") { if let t = model.trimPointSeconds { model.setTrimEnd(atSeconds: t) } }
                    .help("End the sound at the spot you clicked on the waveform (or the playhead)")
            }
            .controlSize(.small)
            .disabled(sample.duration <= 0)

            if let trim {
                HStack(spacing: 8) {
                    Text("\(Format.clock(trim.start)) – \(Format.clock(trim.end))").monospacedDigit()
                    Text("(\(Format.duration(trim.length)) of \(Format.duration(sample.duration)))").foregroundStyle(.secondary)
                }
                .font(.caption)
                HStack {
                    Text("Fade out").font(.caption).foregroundStyle(.secondary)
                    Picker("Fade out", selection: Binding(get: { nearestFade(trim.fadeOut) }, set: { model.setTrimFadeOut($0) })) {
                        ForEach(Self.fades, id: \.seconds) { Text($0.title).tag($0.seconds) }
                    }
                    .labelsHidden().controlSize(.small).frame(width: 90)
                    Spacer()
                    Button { model.playTrim() } label: { Label("Play Trim", systemImage: "play.fill") }
                    Button("Play Full") { model.playSample(sample, fullFile: true) }
                }
                .controlSize(.small)
                HStack {
                    Button("Remove Trim") { model.clearTrim() }
                    Button("Copy To…") { model.exportTrimmed(sample.id) }
                    Spacer()
                    Button("Add to Drum Machine") { model.addToDrums([sample.id]) }
                }
                .controlSize(.small)
                Text("The file is not changed. Drum machine, previews and exports use the trimmed part.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Click the waveform where the sound should start or end, then press Start Here or End Here. The original file stays as it is.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func nearestFade(_ seconds: Double) -> Double {
        Self.fades.map(\.seconds).min { abs($0 - seconds) < abs($1 - seconds) } ?? 0
    }
}
