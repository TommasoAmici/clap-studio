#if NON_COMMERCIAL
import ClapCore
import SwiftUI

/// The bird species heard in a field recording, each with where. A timestamp starts playback there.
struct FieldBirdsSection: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord
    @State private var occurrences: [SpeciesOccurrence] = []

    private static let timestampsShown = 4

    /// Changes when another recording is selected, or its birds are recomputed.
    private var reloadKey: String { "\(sample.id)|\(model.isIndexing)|\(model.isListeningForBirds)|\(model.birdsRevision)" }

    var body: some View {
        Group { content }
            .task(id: reloadKey) {
                occurrences = model.speciesOccurrences(sample.id)
            }
    }

    /// Nothing to show for a recording without birds, unless the search is still running.
    private var isShown: Bool {
        !occurrences.isEmpty || (model.birdsAvailable && (model.isIndexing || model.isListeningForBirds))
    }

    @ViewBuilder private var content: some View {
        if isShown {
            VStack(alignment: .leading, spacing: 6) {
                Text("Birds in this recording").font(.subheadline.bold())
                if occurrences.isEmpty {
                    Text("Listening…").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(occurrences, id: \.scientific) { occurrence in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Label(occurrence.common, systemImage: "bird").help(occurrence.scientific)
                            Text("\(Int((occurrence.confidence * 100).rounded()))%").font(.caption).monospacedDigit()
                                .foregroundStyle(.secondary).help("Confidence of the clearest moment")
                        }
                        HStack(spacing: 4) {
                            ForEach(Array(occurrence.spans.prefix(Self.timestampsShown).enumerated()), id: \.offset) { _, span in
                                Button(Format.timestamp(span.start)) { model.placeStartMarker(atSeconds: span.start) }
                                    .buttonStyle(.bordered).controlSize(.mini).monospacedDigit()
                                    .help("Play from \(Format.timestamp(span.start))")
                            }
                            if occurrence.spans.count > Self.timestampsShown {
                                Text("+\(occurrence.spans.count - Self.timestampsShown)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .font(.caption)
        }
    }
}
#endif
