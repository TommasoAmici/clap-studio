#if NON_COMMERCIAL
import ClapCore
import SwiftUI

/// Bird species in field recordings: whether BirdNET is installed, and the place assumed for recordings.
struct BirdSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var choosing = false
    @State private var place: GeoPoint?

    var body: some View {
        Form {
            Section {
                if model.birdsAvailable {
                    Label("BirdNET is installed. Field recordings are listened to for birds after indexing; birds heard "
                          + "with at least 80% confidence are listed.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("BirdNET is not installed.", systemImage: "exclamationmark.triangle")
                    Text("Run tools/export_birdnet.py (see the README) to create the model files, then index again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("BirdNET is licensed CC BY-NC-SA 4.0 (Cornell Lab of Ornithology and Chemnitz University of "
                     + "Technology): fine for personal use, not for a commercial product.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Bird identification") }
            Section {
                HStack {
                    Text(place?.text ?? "No place set").monospacedDigit().foregroundStyle(place == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose on Map…") { choosing = true }
                        .popover(isPresented: $choosing) { LocationPicker(initial: place) { setPlace($0) } }
                    Button("Clear") { setPlace(nil) }.disabled(place == nil)
                }
                Text("Used for recordings without their own place (set it in a recording's properties). Birds that do "
                     + "not live there are left out.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Where you record") }
        }
        .formStyle(.grouped)
        .onAppear { place = model.defaultLocation }
    }

    private func setPlace(_ point: GeoPoint?) {
        place = point
        model.setDefaultBirdLocation(point)
    }
}
#endif
