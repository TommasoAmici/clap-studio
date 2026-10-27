import ClapCore
import MapKit
import SwiftUI

/// Recordings on a map of the world: one pin per place, sized by how many were made there. A pin narrows the list
/// below to those recordings; the filters above apply to the pins too.
struct PlacesPanel: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        if model.locations.isEmpty {
            emptyState
        } else {
            VSplitView {
                map.frame(minHeight: 200, idealHeight: 340)
                LibraryTableView().frame(minHeight: 160)
            }
        }
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(model.placePins) { pin in
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: pin.center.latitude, longitude: pin.center.longitude),
                           anchor: .center) {
                    PlacePin(count: pin.count, selected: model.placeSelectionID == pin.id)
                        .onTapGesture { model.selectPlace(pin.id) }
                        .help(pin.count == 1 ? "1 recording" : "\(pin.count) recordings")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .modifier(ExtendCanvasBackground())
        .overlay(alignment: .topLeading) { summary }
        .onAppear(perform: fit)
        .onChange(of: model.placesRevision) { fit() }
        .onChange(of: model.placePins.count) { if model.placeSelectionID == nil { fit() } }
    }

    /// Frames every pin with some room around them.
    private func fit() {
        let points = model.placePins.map(\.center)
        guard let first = points.first else { return }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for p in points {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        let span = MKCoordinateSpan(latitudeDelta: min(170, max(0.05, (maxLat - minLat) * 1.4)),
                                    longitudeDelta: min(350, max(0.05, (maxLon - minLon) * 1.4)))
        camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                            span: span))
    }

    private var summary: some View {
        HStack(spacing: 8) {
            let total = model.placePins.reduce(0) { $0 + $1.count }
            Text("\(total) \(total == 1 ? "recording" : "recordings") in \(model.placePins.count) \(model.placePins.count == 1 ? "place" : "places")")
                .font(.caption)
            if model.placeSelection != nil {
                Button("Show All") { model.placeSelectionID = nil }.controlSize(.small)
            }
            Button { fit() } label: { Label("Fit Every Pin", systemImage: "scope") }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless).help("Fit every pin")
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .floatingControls(in: Capsule())
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No recordings with a place yet").font(.title3.bold())
            Text("Places are read from files that carry GPS (phone recordings, many field recorders). To place a recording yourself, "
                 + "select a field recording and choose Recorded at in its properties.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlacePin: View {
    let count: Int
    let selected: Bool

    var body: some View {
        let size = min(34, 16 + CGFloat(log2(Double(max(count, 1)))) * 3)
        ZStack {
            Circle().fill(selected ? Color.accentColor : Color.red.opacity(0.85))
            Circle().strokeBorder(.white, lineWidth: selected ? 2.5 : 1.5)
            if count > 1 { Text("\(count)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
        }
        .frame(width: size, height: size)
        .shadow(radius: 1.5)
    }
}
