import ClapCore
import SwiftUI

/// Joins the chosen sounds into sampler-ready copies with selectable cue regions.
struct JoinSheet: View {
    @Environment(AppModel.self) private var model
    @AppStorage("join.settings") private var settingsData = Data()
    @AppStorage("join.presets") private var presetsData = Data()
    @State private var settings = JoinSettings.almSalmple
    @State private var presets: [SavedJoinPreset] = []
    @State private var showPresetName = false
    @State private var presetName = ""
    @State private var presetError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Join \(model.samplesPhrase(model.joinSources.count))").font(.title3.bold())
            Text("New WAV files keep your trims and sound edits. Original files and their cue points stay unchanged.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Picker("Preset", selection: presetSelection) {
                    Text("ALM Squid Salmple").tag("alm")
                    ForEach(presets) { preset in Text(preset.name).tag(preset.id.uuidString) }
                    Text("Custom").tag("custom")
                }
                Button("Save Preset…") { showPresetName.toggle(); presetError = nil }
                    .disabled(!settings.isValid)
            }
            if showPresetName {
                HStack {
                    TextField("Preset name", text: $presetName).textFieldStyle(.roundedBorder)
                        .onSubmit { if canSavePreset { savePreset() } }
                    Button("Save") { savePreset() }.disabled(!canSavePreset)
                    Button("Cancel") { showPresetName = false }.controlSize(.small)
                }
            }
            if let presetError { Text(presetError).font(.caption).foregroundStyle(.red) }

            Form {
                TextField("File name", text: Bindable(model.join).name, prompt: Text(JoinNaming.defaultName))
                TextField("Maximum length (seconds)", value: $settings.maxSeconds,
                          format: .number.precision(.fractionLength(0...3)))
                TextField("Silence between sounds (seconds)", value: $settings.silenceSeconds,
                          format: .number.precision(.fractionLength(0...3)))
                TextField("Maximum cue sets per file", value: $settings.maxCuePoints, format: .number)
                Picker("Channels", selection: $settings.mono) {
                    Text("Mono").tag(true)
                    Text("Stereo").tag(false)
                }
            }
            Text("Files are named \(JoinNaming.fileName(base: JoinNaming.baseName(model.join.name), number: 1)), \(JoinNaming.fileName(base: JoinNaming.baseName(model.join.name), number: 2)) and so on.")
                .font(.caption).foregroundStyle(.secondary)
            Text("16-bit WAV · 44.1 kHz. One cue set per sound or split piece; source cues are discarded in the copies. More files are made when a limit is reached.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Maximum length: above zero to 300 seconds. Silence: 0–300 seconds. Cue sets: 1–65,536. Longer sounds continue across files without added silence or lost audio.")
                .font(.caption).foregroundStyle(.secondary)
            if !settings.isValid {
                Text(JoinError.invalidSettings.localizedDescription).font(.caption).foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Sound order").font(.subheadline.bold())
                ForEach(Array(model.joinSources.prefix(5).enumerated()), id: \.offset) { index, source in
                    Text("\(index + 1). \(source.name)").lineLimit(1)
                }
                if model.joinSources.count > 5 {
                    Text("and \(model.joinSources.count - 5) more").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Cancel") { model.showJoin = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Folder…") {
                    do {
                        settingsData = try JSONEncoder().encode(settings)
                        model.queueJoin(settings: settings)
                    } catch { presetError = "Could not save the join settings." }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!settings.isValid || model.joinSources.count < 2 || model.isJoining)
            }
        }
        .padding(20)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if let saved = try? JSONDecoder().decode(JoinSettings.self, from: settingsData) { settings = saved }
            if let saved = try? JSONDecoder().decode([SavedJoinPreset].self, from: presetsData) { presets = saved }
            #if DEBUG
            if ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_JOIN_PRESET"] == "1" {
                showPresetName = true
                presetName = "Live set"
            }
            #endif
        }
    }

    private var presetSelection: Binding<String> {
        Binding(get: {
            if settings == .almSalmple { return "alm" }
            return presets.first { $0.settings == settings }?.id.uuidString ?? "custom"
        }, set: { id in
            if id == "alm" { settings = .almSalmple }
            else if let preset = presets.first(where: { $0.id.uuidString == id }) { settings = preset.settings }
        })
    }

    private var canSavePreset: Bool {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        return settings.isValid && !name.isEmpty && name.caseInsensitiveCompare("ALM Squid Salmple") != .orderedSame
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSavePreset else { return }
        var updated = presets
        if let index = updated.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            updated[index].settings = settings
            updated[index].name = name
        } else {
            updated.append(SavedJoinPreset(id: UUID(), name: name, settings: settings))
        }
        do {
            presetsData = try JSONEncoder().encode(updated)
            presets = updated
            presetName = ""
            showPresetName = false
            presetError = nil
        } catch { presetError = "Could not save this preset." }
    }
}

private struct SavedJoinPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var settings: JoinSettings
}
