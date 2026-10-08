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
