import ClapCore
import Foundation

/// Where recordings were made.
extension AppModel {
    func recordingLocation(_ id: Int64) -> GeoPoint? { locations[id] ?? store?.location(sampleID: id) }

    /// The place assumed for recordings without their own.
    var defaultLocation: GeoPoint? { store?.defaultLocation }

    /// Says where recordings were made (nil clears it).
    func setLocation(_ point: GeoPoint?, for ids: [Int64]) {
        guard let store else { return }
        try? store.setLocation(point, sampleIDs: ids)
        reloadLocations()
        #if NON_COMMERCIAL
        placeChangedForBirds(ids)
        #endif
    }

    func reloadLocations() {
        locations = store?.locations() ?? [:]
        placesRevision += 1
        if viewMode == .places { refilter() }
    }
}

extension AppModel {
    /// Shows only what was recorded at a pin (nil: every placed recording).
    func selectPlace(_ id: String?) { placeSelectionID = placeSelectionID == id ? nil : id }

    var placeSelection: PlaceCluster? { placeSelectionID.flatMap { id in placePins.first { $0.id == id } } }
}
