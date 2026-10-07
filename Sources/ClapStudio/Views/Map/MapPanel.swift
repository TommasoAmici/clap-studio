import ClapCore
import SwiftUI

/// SwiftUI host for the Metal map.
struct MetalMapView: NSViewRepresentable {
    @Environment(AppModel.self) private var model

    final class Coordinator {
        var layoutVersion = -1
        var clusterVersion = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MapMTKView {
        let view = MapMTKView()
        view.onHover = { [model] row in model.previewRow(row) }
        view.onClick = { [model] row in
            if let id = model.snapshot?.index.ids[row] { model.select(id, play: true) }
        }
        view.urlForRow = { [model] row in
            guard let id = model.snapshot?.index.ids[row] else { return nil }
            return model.sampleByID[id]?.url
        }
        view.onGrab = { [model] row in
            if let id = model.snapshot?.index.ids[row] { model.registerGrab(id) }
        }
        return view
    }

    func updateNSView(_ view: MapMTKView, context: Context) {
        guard let snap = model.snapshot else { return }
        let c = context.coordinator
        if c.layoutVersion != model.mapVersion {
            c.layoutVersion = model.mapVersion
            c.clusterVersion = model.clusterVersion
            view.setData(xy: snap.xy, clusters: snap.clusters, refit: true)
        } else if c.clusterVersion != model.clusterVersion {
            c.clusterVersion = model.clusterVersion
            view.setClusters(snap.clusters)
        }
        let selectedRow = model.selectedID.flatMap { snap.index.row(forID: $0) }
        view.setSelection(selected: selectedRow, similar: model.similarRows)
    }
}

struct MapPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if model.snapshot != nil {
                MetalMapView()
            } else {
                MapPlaceholder()
            }
        }
        .overlay(alignment: .topLeading) { if model.snapshot != nil { MapControls().padding(12) } }
        .overlay(alignment: .bottomLeading) { if model.snapshot != nil { ClusterLegend().padding(12) } }
        .overlay(alignment: .bottom) { HoverCaption().padding(.bottom, 12) }
    }
}

private struct MapPlaceholder: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            if model.isIndexing { ProgressView() }
            Text(model.isIndexing ? "Building the map once indexing finishes…" : "The map appears after samples are indexed.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.075, blue: 0.09))
    }
}

private struct MapControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            Toggle("Hover to play", isOn: $model.hoverPlay).toggleStyle(.switch).controlSize(.small)
            Divider().frame(height: 16)
            Stepper(value: Binding(get: { model.clusterCount }, set: { model.setClusterCount($0) }), in: 2...Palette.count) {
                Text("\(model.clusterCount) clusters").monospacedDigit()
            }
            Divider().frame(height: 16)
            Button("Re-layout") { model.relayout() }.disabled(model.isIndexing)
                .help("Recompute the whole map. Positions otherwise stay stable between launches.")
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ClusterLegend: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(model.clusterInfo) { c in
                    HStack(spacing: 6) {
                        Circle().fill(Color(nsColor: Palette.color(c.id))).frame(width: 9, height: 9)
                        Text(c.label).lineLimit(1)
                        Text("\(c.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: 230, maxHeight: 190)
        .fixedSize(horizontal: true, vertical: false)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct HoverCaption: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let row = model.hoverRow, let id = model.snapshot?.index.ids[row], let s = model.sampleByID[id] {
            VStack(spacing: 2) {
                Text(s.name).font(.callout.bold())
                Text(s.folder.isEmpty ? " " : s.folder).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
        }
    }
}
