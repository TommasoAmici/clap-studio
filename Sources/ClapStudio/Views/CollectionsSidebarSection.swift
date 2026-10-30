import ClapCore
import SwiftUI

/// The sidebar's collections. A collection with sub-collections has an arrow that shows or hides them; there is one level only.
struct CollectionsSidebarSection: View {
    @Environment(AppModel.self) private var model
    @State private var openCollections: Set<Int64> = []
    @State private var renaming: CollectionRecord?
    @State private var renameText = ""
    @State private var deleting: CollectionRecord?

    /// Room for the arrow is only kept while some collection has sub-collections, so plain lists line up with the other sections.
    private var nested: Bool { model.collections.contains { $0.parentID != nil } }

    var body: some View {
        Section("Collections") {
            ForEach(model.collectionTree) { node in
                row(node.record, hasChildren: node.children != nil)
                if openCollections.contains(node.id) {
                    ForEach(node.children ?? []) { child in row(child.record, hasChildren: false) }
                }
            }
            Button { model.newCollectionParent = nil; model.newCollectionSeed = [] } label: { Label("New Collection", systemImage: "plus") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        // Picking a sub-collection (or making one) shows it.
        .onChange(of: model.collectionSelection) { _, _ in revealSelection() }
        .onChange(of: model.collections) { _, _ in revealSelection() }
        .onAppear(perform: revealSelection)
        .confirmationDialog(deleting.map { "Delete “\($0.name)”?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Collection and Sub-collections", role: .destructive) { if let deleting { model.delete(collection: deleting.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let deleting {
                let count = model.subCollectionCount(of: deleting.id)
                Text("This also deletes its \(count) sub-collection\(count == 1 ? "" : "s"). Your samples and audio files are not deleted, and Undo brings everything back.")
            }
        }
        .alert("Rename Collection", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let renaming { model.rename(collection: renaming.id, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func revealSelection() {
        if let id = model.collectionSelection, let parent = model.collection(id)?.parentID { openCollections.insert(parent) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_NESTED"] == "1" { openCollections.formUnion(model.collections.compactMap(\.parentID)) }
        #endif
    }

    private func row(_ collection: CollectionRecord, hasChildren: Bool) -> some View {
        HStack(spacing: 4) {
            if collection.parentID == nil, nested { disclosure(for: collection, hasChildren: hasChildren) }
            Label(collection.name, systemImage: collection.parentID == nil ? "rectangle.stack" : "rectangle")
            Spacer()
            Text("\(collection.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
        }
        .padding(.leading, collection.parentID == nil ? 0 : 20)
        .tag("col.\(collection.id)")
        .contextMenu { menu(collection) }
    }

    /// The arrow that shows or hides a collection's sub-collections.
    @ViewBuilder
    private func disclosure(for collection: CollectionRecord, hasChildren: Bool) -> some View {
        if hasChildren {
            Button {
                if openCollections.contains(collection.id) { openCollections.remove(collection.id) } else { openCollections.insert(collection.id) }
            } label: {
                Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(openCollections.contains(collection.id) ? 90 : 0))
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .help(openCollections.contains(collection.id) ? "Hide sub-collections" : "Show sub-collections")
            .accessibilityLabel(openCollections.contains(collection.id) ? "Hide sub-collections" : "Show sub-collections")
        } else {
            Color.clear.frame(width: 10, height: 10)
        }
    }

    /// Right-click menu of a collection or sub-collection.
    @ViewBuilder private func menu(_ collection: CollectionRecord) -> some View {
        if collection.parentID == nil {
            Button("New Sub-collection…") {
                openCollections.insert(collection.id)
                model.newCollectionParent = collection.id
                model.newCollectionSeed = []
            }
        }
        Button("Rename…") { renaming = collection; renameText = collection.name }
        if collection.parentID != nil {
            Button("Move to Top Level") { model.move(collection: collection.id, into: nil) }
        } else if model.canNest(collection: collection.id), model.collectionTree.contains(where: { $0.id != collection.id }) {
            Menu("Move Into") {
                ForEach(model.collectionTree.filter { $0.id != collection.id }) { node in
                    Button(node.record.name) {
                        openCollections.insert(node.id)
                        model.move(collection: collection.id, into: node.id)
                    }
                }
            }
        }
        if model.squidEnabled {
            Divider()
            Button("Send to Squid Salmple…") { model.openSquidCollection(collection.id) }
        }
        Divider()
        Button("Delete Collection", role: .destructive) {
            if model.subCollectionCount(of: collection.id) > 0 { deleting = collection } else { model.delete(collection: collection.id) }
        }
    }
}
