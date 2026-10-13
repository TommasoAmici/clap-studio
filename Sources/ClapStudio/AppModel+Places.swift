import ClapCore
import Foundation

extension AppModel {
    func recordingLocation(_ id: Int64) -> GeoPoint? { locations[id] ?? store?.location(sampleID: id) }

    var defaultLocation: GeoPoint? { store?.defaultLocation }

    /// Says where recordings were made (nil clears it).
    func setLocation(_ point: GeoPoint?, for ids: [Int64]) {
        guard let store else { return }
        do { try store.setLocation(point, sampleIDs: ids) } catch { errorMessage = "Could not save the place: \(error)"; return }
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
