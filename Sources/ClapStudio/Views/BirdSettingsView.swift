import ClapCore
import SwiftUI

/// Bird species in field recordings: whether BirdNET is installed, and the place assumed for recordings.
struct BirdSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var placeText = ""

    var body: some View {
        Form {
            Section {
                if model.birdsAvailable {
                    Label("BirdNET is installed. Field recordings are listened to for birds after indexing.",
                          systemImage: "checkmark.circle").foregroundStyle(.secondary)
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
                TextField("Latitude, longitude", text: $placeText).monospacedDigit().onSubmit(commit)
                HStack {
                    Button("Set Place", action: commit).disabled(GeoPoint(parsing: placeText) == nil)
                    Button("Clear") { placeText = ""; commit() }.disabled(model.defaultBirdLocation == nil)
                }
                Text("Used for recordings without their own place (set it in a recording's properties). Birds that do "
                     + "not live there are left out. Decimal degrees, for example 51.5, -0.1.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Where you record") }
        }
        .formStyle(.grouped)
        .onAppear { placeText = model.defaultBirdLocation?.text ?? "" }
    }

    private func commit() {
        let trimmed = placeText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            model.setDefaultBirdLocation(nil)
        } else if let point = GeoPoint(parsing: trimmed) {
            placeText = point.text
            model.setDefaultBirdLocation(point)
        }
    }
}
