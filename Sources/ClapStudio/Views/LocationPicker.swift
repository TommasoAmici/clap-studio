#if NON_COMMERCIAL
import ClapCore
import MapKit
import SwiftUI

/// Pick where a recording was made: search for a place or click the map to drop a pin.
struct LocationPicker: View {
    let initial: GeoPoint?
    let onChoose: (GeoPoint?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: GeoPoint?
    @State private var camera: MapCameraPosition
    @State private var query = ""
    @State private var searchNote: String?

    init(initial: GeoPoint?, onChoose: @escaping (GeoPoint?) -> Void) {
        self.initial = initial
        self.onChoose = onChoose
        _chosen = State(initialValue: initial)
        _camera = State(initialValue: initial.map { Self.region(around: $0) } ?? .automatic)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search for a place", text: $query).textFieldStyle(.roundedBorder).onSubmit(search)
                Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let searchNote { Text(searchNote).font(.caption).foregroundStyle(.secondary) }
            MapReader { proxy in
                Map(position: $camera) {
                    if let chosen {
                        Marker("Recorded here", coordinate: CLLocationCoordinate2D(latitude: chosen.latitude,
                                                                                     longitude: chosen.longitude))
                    }
                }
                .onTapGesture(coordinateSpace: .local) { point in
                    if let coordinate = proxy.convert(point, from: .local) { chosen = Self.point(coordinate) }
                }
            }
            .frame(width: 460, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Text(chosen?.text ?? "Click the map to drop a pin.").font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if initial != nil {
                    Button("Clear Place") { onChoose(nil); dismiss() }
                }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use This Place") { onChoose(chosen); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(chosen == nil || chosen == initial)
            }
        }
        .padding(14)
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searchNote = "Searching…"
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        MKLocalSearch(request: request).start { response, _ in
            Task { @MainActor in
                guard let item = response?.mapItems.first, let point = Self.point(item.placemark.coordinate) else {
                    searchNote = "Nothing found for “\(text)”."
                    return
                }
                searchNote = item.name.map { "Found \($0)." }
                chosen = point
                camera = Self.region(around: point)
            }
        }
    }

    private static func region(around point: GeoPoint) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                                   span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)))
    }

    /// The map can report longitudes beyond ±180 when wrapped around the world.
    static func point(_ coordinate: CLLocationCoordinate2D) -> GeoPoint? {
        let longitude = (coordinate.longitude + 180).truncatingRemainder(dividingBy: 360)
        return GeoPoint(latitude: coordinate.latitude, longitude: (longitude < 0 ? longitude + 360 : longitude) - 180)
    }
}
#endif
