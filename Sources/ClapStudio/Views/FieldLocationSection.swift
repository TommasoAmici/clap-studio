import ClapCore
import SwiftUI

/// Where a field recording was made: read from the file when it says, or picked on a map. With BirdNET the place rules
/// out the birds that do not live there, so changing it listens for them again; a recording without its own place
/// uses the one set for the library.
struct FieldLocationSection: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord

    @State private var place: GeoPoint?
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recorded at").font(.subheadline.bold())
            HStack(spacing: 6) {
                Button(place?.text ?? model.defaultLocation.map { "\($0.text) (library)" } ?? "Choose on Map…") { choosing = true }
                    .buttonStyle(.borderless).monospacedDigit()
                    .popover(isPresented: $choosing) {
                        LocationPicker(initial: place ?? model.defaultLocation) {
                            model.setLocation($0, for: [sample.id])
                            place = $0
                        }
                    }
                if place != nil {
                    Button { model.setLocation(nil, for: [sample.id]); place = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).help("Use the library's place instead")
                }
            }
            #if NON_COMMERCIAL
            if place == nil, model.defaultLocation == nil, model.birdsAvailable {
                Text("Pick a place to rule out birds that do not live there.").font(.caption2).foregroundStyle(.secondary)
            }
            #endif
        }
        .font(.caption)
        .task(id: "\(sample.id)|\(model.birdsRevision)|\(model.placesRevision)") { place = model.recordingLocation(sample.id) }
    }
}
