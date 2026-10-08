import Foundation
import Testing
@testable import ClapCore

@Suite struct SpeciesStoreTests {
    private func recording(duration: Double = 120) throws -> (LibraryStore, Int64) {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "garden.wav", size: 1, mtime: 1)]) { $0 }
        let id = store.pendingJobs(limit: 1)[0].id
        try store.save(results: [.success(id: id, duration: duration, sampleRate: 48000, channels: 1, embedding: [1, 0],
                                          fingerprint: nil, modelVersion: "m1")])
        return (store, id)
    }

    private func bird(_ name: String, _ start: Double, _ confidence: Float, scientific: String? = nil) -> BirdDetection {
        BirdDetection(start: start, end: start + 3, scientific: scientific ?? "Sci \(name)", common: name, confidence: confidence)
    }

    private let robin = "Sci Robin"
    private let parakeet = "Sci Parakeet"

    @Test func locationsRoundTripAndTheRecordingsOwnWins() throws {
        let (store, id) = try recording()
        #expect(store.location(sampleID: id) == nil && store.effectiveLocation(sampleID: id) == nil)
        store.defaultLocation = GeoPoint(latitude: 51.5, longitude: -0.1)
        #expect(store.effectiveLocation(sampleID: id)?.latitude == 51.5)
        try store.setLocation(GeoPoint(latitude: 9.9, longitude: -84), sampleIDs: [id])
        #expect(store.effectiveLocation(sampleID: id)?.longitude == -84)
        try store.setLocation(nil, sampleIDs: [id])
        #expect(store.location(sampleID: id) == nil && store.effectiveLocation(sampleID: id)?.latitude == 51.5)
        store.defaultLocation = nil
        #expect(store.defaultLocation == nil)
        #expect(GeoPoint(latitude: 91, longitude: 0) == nil && GeoPoint(latitude: 0, longitude: 181) == nil)
    }

    @Test func recordingsAreListenedToOnceUntilTheirAudioIsReadAgain() throws {
        let (store, id) = try recording()
        #expect(store.recordingsNeedingSpecies().map(\.id) == [id])
        try store.saveSpecies(sampleID: id, detections: [bird("Robin", 0, 0.9)], allowed: nil)
        #expect(store.recordingsNeedingSpecies().isEmpty)

        // Indexing a recording again (it changed, or the segmenter did) clears what was heard in it.
        try store.save(results: [.success(id: id, duration: 120, sampleRate: 48000, channels: 1, embedding: [1, 0],
                                          fingerprint: nil, modelVersion: "m1",
                                          segments: [SegmentEmbedding(start: 0, end: 5, embedding: [1, 0])])])
        #expect(store.recordingsNeedingSpecies().map(\.id) == [id])
        #expect(store.speciesOccurrences(sampleID: id).isEmpty)
    }

    @Test func shortFilesAreNotListenedTo() throws {
        let (store, _) = try recording(duration: 12)
        #expect(store.recordingsNeedingSpecies().isEmpty)
    }

    @Test func occurrencesMergeNeighbouringWindowsAndRankByHowOftenHeard() throws {
        let (store, id) = try recording()
        try store.saveSpecies(sampleID: id, detections: [
            bird("Robin", 0, 0.5), bird("Robin", 3, 0.9), bird("Robin", 9, 0.4),    // two stretches
            bird("Goldfinch", 6, 0.8),
            bird("Hawfinch", 12, 0.2),                                              // below the reporting cut-off
        ], allowed: nil)
        let found = store.speciesOccurrences(sampleID: id)
        #expect(found.map(\.common) == ["Robin", "Goldfinch"])
        let robin = found[0]
        #expect(robin.windows == 3 && robin.confidence == 0.9 && robin.best.start == 3)
        #expect(robin.spans == [TimeSpan(start: 0, end: 6), TimeSpan(start: 9, end: 12)])
        #expect(store.speciesOccurrences(sampleID: id, minimumConfidence: 0.1).map(\.common).contains("Hawfinch"))
    }

    @Test func aPlaceRulesOutSpeciesWithoutListeningAgain() throws {
        let (store, id) = try recording()
        let detections = [bird("Robin", 0, 0.9, scientific: robin), bird("Parakeet", 3, 0.8, scientific: parakeet)]
        try store.saveSpecies(sampleID: id, detections: detections, allowed: [robin])
        #expect(store.speciesOccurrences(sampleID: id).map(\.common) == ["Robin"])
        #expect(store.sample(id: id)?.species == ["Robin"])

        try store.refilterSpecies(sampleID: id, allowed: [robin, parakeet])
        #expect(Set(store.speciesOccurrences(sampleID: id).map(\.common)) == ["Robin", "Parakeet"])
        try store.refilterSpecies(sampleID: id, allowed: [parakeet])
        #expect(store.speciesOccurrences(sampleID: id).map(\.common) == ["Parakeet"])
        try store.refilterSpecies(sampleID: id, allowed: nil)                    // no place: nothing is ruled out
        #expect(store.speciesOccurrences(sampleID: id).count == 2)
        #expect(store.recordingsWithSpecies() == [id])
    }

    @Test func sidebarCountsRecordingsPerSpecies() throws {
        let (store, id) = try recording()
        try store.saveSpecies(sampleID: id, detections: [bird("Robin", 0, 0.9), bird("Robin", 3, 0.9), bird("Wren", 6, 0.7)],
                              allowed: nil)
        let counts = store.speciesCounts()
        #expect(counts.map(\.common) == ["Robin", "Wren"] && counts.allSatisfy { $0.recordings == 1 })
    }

    @Test func removingARootForgetsItsSpecies() throws {
        let (store, id) = try recording()
        try store.saveSpecies(sampleID: id, detections: [bird("Robin", 0, 0.9)], allowed: nil)
        try store.removeRoot(id: try #require(store.roots().first?.id))
        #expect(store.recordingsWithSpecies().isEmpty)
    }

    @Test func theFilterMatchesSpeciesHeardInARecording() {
        var sample = SampleRecord(id: 1, rootID: 1, rootPath: "/", relPath: "a.wav", name: "a", ext: "wav", duration: 120,
                                  sampleRate: 48000, channels: 1, size: 1, mtime: 1, status: .ok, useCount: 0,
                                  lastUsed: nil, cueCount: 0)
        sample.species = ["European Robin"]
        var filter = DescriptorFilter()
        filter.species = "European Robin"
        #expect(filter.matches(sample))
        filter.species = "Hawfinch"
        #expect(!filter.matches(sample))
    }
}
