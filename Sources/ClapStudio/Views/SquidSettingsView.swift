import SwiftUI

struct SquidSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Squid Salmple support", isOn: $model.squidEnabled)
                Text("Shows connected USB drives in the sidebar, so the banks, sets and Pool on a stick can be browsed and heard, "
                     + "and lets you send up to eight samples at a time to a bank. Samples on a stick are analysed while you use them "
                     + "but are not added to your library, and nothing on a stick is ever changed except by sending samples to it.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Busy Circuits Squid Salmple (ALM022)") }
        }
        .formStyle(.grouped)
    }
}
