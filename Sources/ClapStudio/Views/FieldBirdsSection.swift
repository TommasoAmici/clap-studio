import ClapCore
import SwiftUI

/// The bird species heard in a field recording, each with where, and where the recording was made (which rules
/// out species that do not live there). A timestamp starts playback there; a name shows every recording with it.
struct FieldBirdsSection: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord
    @State private var occurrences: [SpeciesOccurrence] = []
    @State private var place: GeoPoint?
    @State private var placeText = ""

    private static let timestampsShown = 4

    /// Changes when another recording is selected or its species are recomputed.
    private var reloadKey: String { "\(sample.id)|\(sample.species.joined(separator: ","))|\(model.isIndexing)" }

    var body: some View {
        Group { content }
            .task(id: reloadKey) {
                occurrences = model.speciesOccurrences(sample.id)
                place = model.recordingLocation(sample.id)
                placeText = place?.text ?? ""
            }
    }

    @ViewBuilder private var content: some View {
        if model.birdsAvailable || !occurrences.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Birds in this recording").font(.subheadline.bold())
                if occurrences.isEmpty {
                    Text(model.isIndexing ? "Listening…" : "No birds identified.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(occurrences, id: \.scientific) { occurrence in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Button { model.descriptorFilter.species = occurrence.common } label: {
                                Label(occurrence.common, systemImage: "bird")
                            }
                            .buttonStyle(.borderless)
                            .help("\(occurrence.scientific). Show every recording with this bird")
                            Text("\(Int((occurrence.confidence * 100).rounded()))%").font(.caption).monospacedDigit()
                                .foregroundStyle(.secondary).help("Most confident listening window")
                        }
                        HStack(spacing: 4) {
                            Button(Format.timestamp(occurrence.best.start)) { model.placeStartMarker(atSeconds: occurrence.best.start) }
                                .buttonStyle(.borderedProminent).controlSize(.mini).monospacedDigit()
                                .help("Most confident: play from \(Format.timestamp(occurrence.best.start))")
                            ForEach(Array(others(of: occurrence).prefix(Self.timestampsShown - 1).enumerated()), id: \.offset) { _, span in
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

    /// The other stretches, in time order (the first one already has the most confident button).
    private func others(of occurrence: SpeciesOccurrence) -> [TimeSpan] {
        occurrence.spans.filter { !($0.start <= occurrence.best.start && occurrence.best.start < $0.end) }
    }

    private var locationRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Recorded at").foregroundStyle(.secondary)
                TextField(model.defaultBirdLocation?.text ?? "latitude, longitude", text: $placeText)
                    .textFieldStyle(.roundedBorder).monospacedDigit().frame(maxWidth: 150)
                    .onSubmit(commit)
                if place != nil {
                    Button { placeText = ""; commit() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).help("Use the library's place instead")
                }
            }
            if place == nil, model.defaultBirdLocation == nil {
                Text("Add a place (decimal degrees, e.g. 51.5, -0.1) to rule out birds that do not live there.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if invalidText {
                Text("Latitude, then longitude, in decimal degrees.").font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private var invalidText: Bool {
        !placeText.trimmingCharacters(in: .whitespaces).isEmpty && GeoPoint(parsing: placeText) == nil
    }

    private func commit() {
        let trimmed = placeText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            place = nil
            model.setLocation(nil, for: [sample.id])
        } else if let point = GeoPoint(parsing: trimmed) {
            place = point
            placeText = point.text
            model.setLocation(point, for: [sample.id])
        }
    }
}
