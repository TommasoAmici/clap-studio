import ClapCore
import SwiftUI

/// A scratch list of samples to drag into a DAW together, copy to a folder, or keep as a collection.
struct TrayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let samples = model.traySamples
        if !samples.isEmpty {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Label("Tray (\(samples.count))", systemImage: "tray.full").font(.caption.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(samples) { s in chip(s) }
                        }
                    }
                    FileDragHandle(urls: samples.map(\.url), label: "Drag all \(samples.count)") { model.registerTrayGrab() }
                        .frame(width: 130, height: 30)
                    Button("Try in Drums") { model.addToDrums(samples.map(\.id)) }
                        .help("Load these into the drum machine")
                    Button("Copy To…") { model.showExport = true }
                        .help("Copy these files into a folder")
                    Button("Save as Collection") { model.newCollectionSeed = samples.map(\.id) }
                    Button { model.clearTray() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).help("Empty the tray")
                }
                .controlSize(.small)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.bar)
            }
        }
    }

    private func chip(_ s: SampleRecord) -> some View {
        HStack(spacing: 4) {
            Text(s.name).lineLimit(1).font(.caption)
            Button { model.removeFromTray(s.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .onTapGesture { model.select(s.id, play: true) }
    }
}

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
