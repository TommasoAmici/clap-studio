import ClapCore
import SwiftUI

/// Asks for a name, then creates the collection with whatever samples triggered the prompt.
struct NewCollectionPrompt: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("New Collection", isPresented: Binding(get: { model.newCollectionSeed != nil },
                                                             set: { if !$0 { model.newCollectionSeed = nil } })) {
            TextField("Name", text: $name)
            Button("Create") {
                model.createCollection(named: name, with: model.newCollectionSeed ?? [])
                name = ""
            }
            Button("Cancel", role: .cancel) { name = "" }
        } message: {
            if let seed = model.newCollectionSeed, !seed.isEmpty { Text("Starts with \(seed.count) sample\(seed.count == 1 ? "" : "s").") }
        }
    }
}

/// Asks for a tag name and applies it to the samples that triggered the prompt.
struct AddTagPrompt: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var text = ""

    func body(content: Content) -> some View {
        content.alert("Add Tag", isPresented: Binding(get: { model.tagPromptTargets != nil },
                                                      set: { if !$0 { model.tagPromptTargets = nil } })) {
            TextField("Tag", text: $text)
            Button("Add") {
                model.addTag(text, to: model.tagPromptTargets ?? [])
                text = ""
            }
            Button("Cancel", role: .cancel) { text = "" }
        } message: {
            if let targets = model.tagPromptTargets { Text("For \(model.samplesPhrase(targets.count)).") }
        }
    }
}

/// Confirms writing category, tags and moods into the selected WAV files.
struct WriteTagsPrompt: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.alert("Write Tags into Files", isPresented: Binding(get: { model.tagWriteTargets != nil },
                                                                    set: { if !$0 { model.tagWriteTargets = nil } })) {
            Button("Write") { model.writeTagsToFiles(model.tagWriteTargets ?? [], keepBackup: false) }
            Button("Write, Keep Backups") { model.writeTagsToFiles(model.tagWriteTargets ?? [], keepBackup: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let targets = model.tagWriteTargets {
                Text("Puts the category, tags and moods of \(model.samplesPhrase(targets.count)) into the WAV files themselves "
                     + "(the genre and keywords of the file's INFO list), so other software and a re-imported library see them. "
                     + "The audio is not changed.")
            }
        }
    }
}
