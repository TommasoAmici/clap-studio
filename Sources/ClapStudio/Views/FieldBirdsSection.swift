import ClapCore
import SwiftUI

/// The bird species heard in a field recording, each with where, and where the recording was made (which rules
/// out species that do not live there). A timestamp starts playback there.
struct FieldBirdsSection: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord
    @State private var occurrences: [SpeciesOccurrence] = []
    @State private var place: GeoPoint?
    @State private var choosing = false

    private static let timestampsShown = 4

    /// Changes when another recording is selected, or its birds or place are recomputed.
    private var reloadKey: String { "\(sample.id)|\(model.isIndexing)|\(model.isListeningForBirds)|\(model.birdsRevision)" }

    var body: some View {
        Group { content }
            .task(id: reloadKey) {
                occurrences = model.speciesOccurrences(sample.id)
                place = model.recordingLocation(sample.id)
            }
    }

    @ViewBuilder private var content: some View {
        if model.birdsAvailable || !occurrences.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Birds in this recording").font(.subheadline.bold())
                if occurrences.isEmpty {
                    Text((model.isIndexing || model.isListeningForBirds) ? "Listening…" : "No birds identified with confidence.")
                        .font(.caption).foregroundStyle(.secondary)
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
                locationRow
            }
            .font(.caption)
        }
    }

    private var locationRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Recorded at").foregroundStyle(.secondary)
                Button(place?.text ?? model.defaultBirdLocation.map { "\($0.text) (library)" } ?? "Choose on Map…") { choosing = true }
                    .buttonStyle(.borderless).monospacedDigit()
                    .popover(isPresented: $choosing) {
                        LocationPicker(initial: place ?? model.defaultBirdLocation) { model.setLocation($0, for: [sample.id]) }
                    }
                if place != nil {
                    Button { model.setLocation(nil, for: [sample.id]) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).help("Use the library's place instead")
                }
            }
            if place == nil, model.defaultBirdLocation == nil {
                Text("Pick a place to rule out birds that do not live there.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
