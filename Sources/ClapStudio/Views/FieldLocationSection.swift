#if NON_COMMERCIAL
import ClapCore
import SwiftUI

/// Where a field recording was made. The place rules out the birds that do not live there, so changing it
/// listens for them again; a recording without its own place uses the one set for the library.
struct FieldLocationSection: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord

    @State private var place: GeoPoint?
    @State private var choosing = false

    var body: some View {
        if model.birdsAvailable {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recorded at").font(.subheadline.bold())
                HStack(spacing: 6) {
                    Button(place?.text ?? model.defaultBirdLocation.map { "\($0.text) (library)" } ?? "Choose on Map…") { choosing = true }
                        .buttonStyle(.borderless).monospacedDigit()
                        .popover(isPresented: $choosing) {
                            LocationPicker(initial: place ?? model.defaultBirdLocation) {
                                model.setLocation($0, for: [sample.id])
                                place = $0
                            }
                        }
                    if place != nil {
                        Button { model.setLocation(nil, for: [sample.id]); place = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).help("Use the library's place instead")
                    }
                }
                if place == nil, model.defaultBirdLocation == nil {
                    Text("Pick a place to rule out birds that do not live there.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .task(id: "\(sample.id)|\(model.birdsRevision)") { place = model.recordingLocation(sample.id) }
        }
    }
}
#endif
