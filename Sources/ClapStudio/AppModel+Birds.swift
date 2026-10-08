#if NON_COMMERCIAL
import ClapCore
import Foundation

/// Bird species heard in field recordings (BirdNET, see `tools/export_birdnet.py`).
extension AppModel {
    /// The BirdNET model files are installed, so field recordings can be listened to.
    var birdsAvailable: Bool { BirdClassifier.isInstalled && ModelLocator.exists(BirdLocationModel.modelName) }

    func speciesOccurrences(_ id: Int64) -> [SpeciesOccurrence] { store?.speciesOccurrences(sampleID: id) ?? [] }

    func recordingLocation(_ id: Int64) -> GeoPoint? { store?.location(sampleID: id) }

    var defaultBirdLocation: GeoPoint? { store?.defaultLocation }

    /// Listens to every field recording not yet listened to. Needs no progress UI beyond the status line.
    nonisolated static func listenForBirds(_ store: LibraryStore, token: CancelToken,
                                           report: @escaping @Sendable (String) -> Void) {
        guard let classifier = try? BirdClassifier.load().get(), let labels = BirdLabels.load() else { return }
        let filter = (try? BirdLocationModel.load().get()).map { BirdLocationFilter(model: $0, labels: labels) }
        BirdSpeciesIndexer.run(store: store, detector: BirdDetector(classifier: classifier, labels: labels), filter: filter,
                               onProgress: { done, total, name in
                                   if total > 0, done < total { report("Listening for birds (\(done + 1)/\(total)): \(name)") }
                               }, isCancelled: { token.isCancelled })
    }

    /// Says where recordings were made (nil clears it), which rules out species that do not live there.
    func setLocation(_ point: GeoPoint?, for ids: [Int64]) {
        guard let store else { return }
        try? store.setLocation(point, sampleIDs: ids)
        store.forgetSpecies(sampleIDs: ids)
        refilterSpecies(ids)
    }

    /// The place assumed for recordings without their own.
    func setDefaultBirdLocation(_ point: GeoPoint?) {
        guard let store else { return }
        store.defaultLocation = point
        store.forgetSpeciesWithoutOwnPlace()
        refilterSpecies(nil)
    }

    private func refilterSpecies(_ ids: [Int64]?) {
        guard let store else { return }
        Task {
            await Task.detached {
                let labels = BirdLabels.load()
                let filter = labels.flatMap { labels in
                    (try? BirdLocationModel.load().get()).map { BirdLocationFilter(model: $0, labels: labels) }
                }
                BirdSpeciesIndexer.refilter(store: store, filter: filter, sampleIDs: ids)
            }.value
            birdsRevision += 1
            listenAgainForBirds()
        }
    }

    /// Listens again to recordings whose place changed, so the place applies before the per-window limit.
    /// While indexing, that run reaches them instead.
    private func listenAgainForBirds() {
        guard let store, birdsAvailable, !isIndexing, !isListeningForBirds,
              !store.recordingsNeedingSpecies().isEmpty else { return }
        isListeningForBirds = true
        let token = CancelToken()
        Task {
            await Task.detached {
                Self.listenForBirds(store, token: token) { message in Task { @MainActor in self.statusMessage = message } }
            }.value
            statusMessage = ""
            isListeningForBirds = false
            birdsRevision += 1
        }
    }
}
#endif
