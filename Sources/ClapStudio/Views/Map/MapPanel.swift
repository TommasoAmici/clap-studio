import ClapCore
import SwiftUI

/// SwiftUI host for the Metal map.
struct MetalMapView: NSViewRepresentable {
    @Environment(AppModel.self) private var model

    final class Coordinator {
        var layoutVersion = -1
        var clusterVersion = -1
        var filterVersion = -1
        var colorVersion = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MapMTKView {
        let view = MapMTKView()
        view.onHover = { [model] row in model.previewRow(row) }
        view.onClick = { [model] row in
            if let id = model.snapshot?.index.ids[row] { model.select(id, play: true) }
        }
        view.menuForRow = { [model] row in
            guard let id = model.snapshot?.index.ids[row] else { return nil }
            // On a dot picked with the lasso the menu acts on the whole pick; otherwise on that one sample.
            let ids: [Int64]
            if model.mapSelection.count > 1, model.mapSelection.contains(id) { ids = model.mapSelection }
            else { model.select(id); ids = [id] }
            return NSMenu(entries: model.sampleMenu(for: ids))
        }
        view.urlForRow = { [model] row in
            guard let id = model.snapshot?.index.ids[row] else { return nil }
            return model.sampleByID[id]?.url
        }
        view.onGrab = { [model] row in
            if let id = model.snapshot?.index.ids[row] { model.registerGrab(id) }
        }
        view.onLasso = { [model] rows in model.selectOnMap(rows: rows) }
        return view
    }

    func updateNSView(_ view: MapMTKView, context: Context) {
        guard let snap = model.snapshot else { return }
        let c = context.coordinator
        let layoutChanged = c.layoutVersion != model.mapVersion
        if layoutChanged {
            c.layoutVersion = model.mapVersion
            c.clusterVersion = model.clusterVersion
            view.setData(xy: model.axisLayout?.xy ?? snap.xy, clusters: snap.clusters, refit: true)
            c.colorVersion = -1
        } else if c.clusterVersion != model.clusterVersion {
            c.clusterVersion = model.clusterVersion
            view.setClusters(snap.clusters)
        }
        if c.colorVersion != model.mapColorVersion {
            c.colorVersion = model.mapColorVersion
            if let coloring = model.mapColoring {
                view.setColoring(indices: coloring.indices.map(Int.init), palette: coloring.palette)
            } else {
                view.setColoring(indices: snap.clusters.map(Int.init), palette: nil)
            }
        }
        if c.filterVersion != model.filterVersion || layoutChanged {
            c.filterVersion = model.filterVersion
            view.setVisibility(model.mapMask(for: snap))
        }
        let selectedRow = model.selectedID.flatMap { snap.index.row(forID: $0) }
        let marked = model.mapSelection.compactMap { snap.index.row(forID: $0) }
        let drums = model.drumTracks.keys.compactMap { snap.index.row(forID: $0) }.sorted()
        view.setSelection(selected: selectedRow, similar: model.similarRows, marked: marked, drums: drums)
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
        .modifier(ExtendCanvasBackground())
        .overlay(alignment: .topLeading) { if model.snapshot != nil { MapControls().padding(12) } }
        .overlay(alignment: .topTrailing) { if model.searchPending { SearchingBadge().padding(12) } }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 12) {
                    if model.snapshot != nil { ClusterLegend() }
                    Spacer(minLength: 0)
                    HoverCaption()
                    Spacer(minLength: 0)
                }
                if !model.mapSelection.isEmpty { MapSelectionBar() }
            }
            .padding(12)
        }
        .modifier(FloatingControlsContainer())
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
        .background(MapTheme.backgroundColor)
    }
}

private struct MapControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                playbackControls
                Divider().frame(height: 16)
                layoutControls
            }
            VStack(alignment: .leading, spacing: 10) {
                playbackControls
                layoutControls
            }
        }
        .font(.callout)
        .controlSize(.small)
        .padding(12)
        .floatingControls(in: RoundedRectangle(cornerRadius: 16))
    }

    private var playbackControls: some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Toggle("Hover to play", isOn: $model.hoverPlay).toggleStyle(.switch).controlSize(.small)
            Divider().frame(height: 16)
            Stepper(value: Binding(get: { model.clusterCount }, set: { model.setClusterCount($0) }), in: 2...Palette.clusterLimit) {
                Text("\(model.clusterCount) clusters").monospacedDigit()
            }
        }
        .fixedSize()
    }

    private var layoutControls: some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Menu {
                Picker("Colour by", selection: $model.mapColorMode) {
                    ForEach(MapColorMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: { Label("Colour: \(model.mapColorMode.rawValue)", systemImage: "paintpalette") }
            .menuStyle(.button).fixedSize()
            Menu {
                Button("By similarity") { model.mapAxes = nil }
                Divider()
                Menu("Horizontal axis") {
                    ForEach(MapProperty.allCases) { p in Button(p.rawValue) { model.mapAxes = (p, model.mapAxes?.y ?? defaultY(besides: p)) } }
                }
                Menu("Vertical axis") {
                    ForEach(MapProperty.allCases) { p in Button(p.rawValue) { model.mapAxes = (model.mapAxes?.x ?? defaultX(besides: p), p) } }
                }
            } label: {
                Label(model.mapAxes.map { "\($0.x.rawValue) × \($0.y.rawValue)" } ?? "Layout: similarity", systemImage: "chart.xyaxis.line")
            }
            .menuStyle(.button).fixedSize()
            Divider().frame(height: 16)
            Button("Re-layout") { model.relayout() }.disabled(model.isIndexing)
                .help("Recompute the whole map. Positions otherwise stay stable between launches.")
        }
        .fixedSize()
    }
}

private func defaultX(besides other: MapProperty) -> MapProperty { other == .brightness ? .loudness : .brightness }
private func defaultY(besides other: MapProperty) -> MapProperty { other == .loudness ? .brightness : .loudness }

private struct ClusterLegend: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let coloring = model.mapColoring { propertyLegend(coloring) } else { clusters }
    }

    private func propertyLegend(_ coloring: MapColoring) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let gradient = coloring.gradient {
                LinearGradient(colors: (0..<22).map { Color(nsColor: coloring.palette[$0]) }, startPoint: .leading, endPoint: .trailing)
                    .frame(width: 160, height: 8).clipShape(Capsule())
                HStack { Text(gradient.low); Spacer(); Text(gradient.high) }.font(.caption2).frame(width: 160)
                Text("Grey: not measured").font(.caption2).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(coloring.legend) { entry in
                            HStack(spacing: 6) {
                                Circle().fill(Color(nsColor: coloring.palette[entry.id])).frame(width: 9, height: 9)
                                Text(entry.label).lineLimit(1)
                                Text("\(entry.count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
        .padding(10)
        .fixedSize()
        .floatingInformation(in: RoundedRectangle(cornerRadius: 10))
    }

    private var clusters: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(model.clusterInfo) { c in
                    HStack(spacing: 6) {
                        Circle().fill(Color(nsColor: Palette.color(c.id))).frame(width: 9, height: 9)
                        Text(c.label).lineLimit(1)
                        Text("\(c.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.caption)
                    .help(c.detail)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: 300, maxHeight: 190)
        .fixedSize(horizontal: true, vertical: false)
        .floatingInformation(in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct HoverCaption: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let row = model.hoverRow, let id = model.snapshot?.index.ids[row], let s = model.sampleByID[id] {
            VStack(spacing: 2) {
                Text(s.name).font(.callout.bold()).lineLimit(1)
                Text(s.folder.isEmpty ? " " : s.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .floatingInformation(in: RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
        }
    }
}

/// Actions for the dots picked with the lasso (shift-drag).
private struct MapSelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Text("\(model.mapSelection.count) selected").font(.callout.bold())
            Button("Copy To…") { model.openExport(ids: model.mapSelection) }
            Menu("Add to Collection") {
                ForEach(model.collections) { c in Button(c.name) { model.add(model.mapSelection, toCollection: c.id) } }
                if !model.collections.isEmpty { Divider() }
                Button("New Collection…") { model.newCollectionSeed = model.mapSelection }
            }
            .fixedSize()
            Button("Favorite") { model.toggleFavorite(model.mapSelection) }
            Button("Tag…") { model.tagPromptTargets = model.mapSelection }
            Button("Hide") { model.hide(model.mapSelection); model.clearMapSelection() }
            Button { model.clearMapSelection() } label: { Label("Clear Selection", systemImage: "xmark") }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("Clear the map selection")
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .floatingControls(in: Capsule())
    }
}
