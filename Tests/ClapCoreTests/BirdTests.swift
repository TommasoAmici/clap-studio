import Foundation
import Testing
@testable import ClapCore

/// The chirp `tools/export_birdnet.py --reference` used to produce `BirdNetReference`.
private func chirp(_ i: Int) -> Float {
    let t = Double(i) / 48_000
    return Float(0.5 * sin(2 * .pi * (2500 * t + 900 * t * t)) * max(0, sin(2 * .pi * 2.5 * t)))
}

@Suite struct BirdLabelTests {
    @Test func parsesScientificAndCommonNames() {
        let labels = BirdLabels(text: "Erithacus rubecula_European Robin\nColumba palumbus_Common Wood-Pigeon\n\nbroken line\n")
        #expect(labels.species.count == 2)
        #expect(labels.species[0] == BirdSpecies(scientific: "Erithacus rubecula", common: "European Robin"))
        #expect(labels.index(ofScientific: "Columba palumbus") == 1)
        #expect(labels.index(ofScientific: "Nothing here") == nil)
    }

    @Test func weekRunsFromOneToFortyEight() {
        let calendar = Calendar(identifier: .gregorian)
        func week(_ y: Int, _ m: Int, _ d: Int) -> Int {
            BirdLocationModel.week(of: calendar.date(from: DateComponents(year: y, month: m, day: d))!, calendar: calendar)
        }
        #expect(week(2026, 1, 1) == 1)
        #expect(week(2026, 12, 31) == 48)
        #expect(week(2026, 7, 2) >= 24 && week(2026, 7, 2) <= 25)
    }

    @Test func probabilityIsASigmoidClippedAtFifteen() {
        #expect(BirdDetector.probability(0) == 0.5)
        #expect(abs(BirdDetector.probability(2) - 0.8808) < 1e-3)
        #expect(BirdDetector.probability(100) == BirdDetector.probability(15))
        #expect(BirdDetector.probability(-100) < 1e-6)
    }
}

@Suite(.enabled(if: BirdClassifier.isInstalled)) struct BirdModelTests {
    @Test func classifierMatchesTheOriginalModel() throws {
        let classifier = try BirdClassifier.load().get()
        let clip = (0..<BirdClassifier.windowSamples).map(chirp)
        let logits = try classifier.logits(clip)
        #expect(logits.count == BirdClassifier.speciesCount)
        for (index, expected) in BirdNetReference.topLogits {
            #expect(abs(logits[index] - expected) < 2e-3)
        }
        let order = logits.indices.sorted { logits[$0] > logits[$1] }
        #expect(Array(order.prefix(5)) == BirdNetReference.topLogits.map(\.index))
    }

    @Test func locationModelMatchesTheOriginalModel() throws {
        let model = try BirdLocationModel.load().get()
        let point = BirdNetReference.locationPoint
        let probabilities = try model.probabilities(latitude: Double(point.lat), longitude: Double(point.lon),
                                                    week: Int(point.week))
        #expect(probabilities.count == BirdClassifier.speciesCount)
        for (index, expected) in BirdNetReference.topLocation {
            #expect(abs(probabilities[index] - expected) < 2e-3)
        }
        #expect(probabilities.filter { $0 >= 0.01 }.count == BirdNetReference.locationAbove001)

        // No week means year-round; it must still run and differ from a single week only slightly.
        let yearRound = try model.probabilities(latitude: Double(point.lat), longitude: Double(point.lon), week: nil)
        #expect(yearRound.count == BirdClassifier.speciesCount)
    }

    @Test func locationRulesOutBirdsFromTheOtherSideOfTheWorld() throws {
        let labels = try #require(BirdLabels.load())
        let model = try BirdLocationModel.load().get()
        let robin = try #require(labels.index(ofScientific: "Erithacus rubecula"))
        let london = try model.probabilities(latitude: 51.5, longitude: -0.1, week: 20)
        let costaRica = try model.probabilities(latitude: 9.9, longitude: -84, week: 20)
        #expect(london[robin] > BirdLocationModel.defaultThreshold)
        #expect(costaRica[robin] < BirdLocationModel.defaultThreshold)
    }

    @Test func detectorListensToWholeWindowsAndSkipsSilence() throws {
        let classifier = try BirdClassifier.load().get()
        let labels = try #require(BirdLabels.load())
        let detector = BirdDetector(classifier: classifier, labels: labels)
        let dir = TestSupport.tempDir()
        let file = dir.appendingPathComponent("silence-then-chirp.wav")
        // 6 s of digital silence, then 7 s of chirp: 3 windows of audio, the last one 1 s long.
        try writeTestWav(file, seconds: 13, sampleRate: 48_000) { t in t < 6 ? 0 : chirp(Int(t * 48_000)) }
        let found = try #require(try detector.detect(url: file, duration: 13))
        #expect(found.allSatisfy { $0.start >= 6 })                 // nothing is reported for the silent part
        #expect(found.allSatisfy { $0.end <= 13 && $0.end > $0.start })
        #expect(found.allSatisfy { $0.confidence >= BirdDetector.candidateFloor })
        #expect(try detector.detect(url: file, duration: 13, isCancelled: { true }) == nil)
    }

    @Test func locationFilterListsTheSpeciesOfAPlace() throws {
        let labels = try #require(BirdLabels.load())
        let filter = BirdLocationFilter(model: try BirdLocationModel.load().get(), labels: labels)
        let london = try filter.allowed(at: try #require(GeoPoint(latitude: 51.5, longitude: -0.1)))
        #expect(london.contains("Erithacus rubecula") && !london.contains("Basileuterus rufifrons"))
        #expect(london.count > 100 && london.count < 1000)
        #expect(try filter.allowed(at: try #require(GeoPoint(latitude: 51.5, longitude: -0.1))) == london)   // cached
    }

    @Test func indexerListensToRecordingsOnceAndHonoursCancellation() throws {
        let classifier = try BirdClassifier.load().get()
        let labels = try #require(BirdLabels.load())
        let detector = BirdDetector(classifier: classifier, labels: labels)
        let dir = TestSupport.tempDir()
        try writeTestWav(dir.appendingPathComponent("field.wav"), seconds: 35, sampleRate: 48_000) { chirp(Int($0 * 48_000)) }
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        let id = store.pendingJobs(limit: 1)[0].id
        try store.save(results: [.success(id: id, duration: 35, sampleRate: 48_000, channels: 1, embedding: [1, 0],
                                          fingerprint: nil, modelVersion: "m1")])
        store.defaultLocation = GeoPoint(latitude: 51.5, longitude: -0.1)
        let filter = BirdLocationFilter(model: try BirdLocationModel.load().get(), labels: labels)

        #expect(BirdSpeciesIndexer.run(store: store, detector: detector, filter: filter, isCancelled: { true }) == 0)
        #expect(store.recordingsNeedingSpecies().count == 1)
        #expect(BirdSpeciesIndexer.run(store: store, detector: detector, filter: filter) == 1)
        #expect(store.recordingsNeedingSpecies().isEmpty)
        #expect(BirdSpeciesIndexer.run(store: store, detector: detector, filter: filter) == 0)
        BirdSpeciesIndexer.refilter(store: store, filter: filter)               // runs without error on any library
    }

    /// Set BIRDNET_SAMPLE to a recording of European garden birds to check the whole path on real audio.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BIRDNET_SAMPLE"] != nil))
    func findsRobinsInARealRecording() throws {
        let path = try #require(ProcessInfo.processInfo.environment["BIRDNET_SAMPLE"])
        let detector = BirdDetector(classifier: try BirdClassifier.load().get(), labels: try #require(BirdLabels.load()))
        let info = try AudioDecoder.fileInfo(url: URL(fileURLWithPath: path))
        let started = Date()
        let found = try #require(try detector.detect(url: URL(fileURLWithPath: path), duration: info.duration))
        print("birdnet: \(found.count) candidates in \(Date().timeIntervalSince(started)) s for \(info.duration) s of audio")
        let robins = found.filter { $0.common == "European Robin" && $0.confidence >= 0.3 }
        #expect(robins.count >= 10)
        #expect(found.contains { $0.common == "European Goldfinch" && $0.confidence >= 0.3 })
    }

    /// The whole path on a real recording: listen, store, and let a place rule birds out and back in.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BIRDNET_SAMPLE"] != nil))
    func aPlaceChangesWhichBirdsAreReportedForARealRecording() throws {
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["BIRDNET_SAMPLE"]))
        let dir = TestSupport.tempDir()
        try FileManager.default.copyItem(at: source, to: dir.appendingPathComponent("garden.wav"))
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        let id = store.pendingJobs(limit: 1)[0].id
        let info = try AudioDecoder.fileInfo(url: dir.appendingPathComponent("garden.wav"))
        try store.save(results: [.success(id: id, duration: info.duration, sampleRate: info.sampleRate, channels: 1,
                                          embedding: [1, 0], fingerprint: nil, modelVersion: "m1")])
        let labels = try #require(BirdLabels.load())
        let filter = BirdLocationFilter(model: try BirdLocationModel.load().get(), labels: labels)
        let detector = BirdDetector(classifier: try BirdClassifier.load().get(), labels: labels)

        // Without a place nothing is ruled out, so far-away species can appear.
        BirdSpeciesIndexer.run(store: store, detector: detector, filter: filter)
        let unfiltered = Set(store.speciesOccurrences(sampleID: id).map(\.common))
        #expect(unfiltered.contains("European Robin"))

        try store.setLocation(GeoPoint(latitude: 51.5, longitude: -0.1), sampleIDs: [id])
        BirdSpeciesIndexer.refilter(store: store, filter: filter)
        let london = store.speciesOccurrences(sampleID: id)
        #expect(london.map(\.common).contains("European Robin"))
        #expect(!london.map(\.common).contains("Crimson-fronted Parakeet"))
        #expect(london.first?.common == "European Robin" && london.first!.windows >= 5)

        try store.setLocation(GeoPoint(latitude: 9.9, longitude: -84), sampleIDs: [id])
        BirdSpeciesIndexer.refilter(store: store, filter: filter)
        #expect(!store.speciesOccurrences(sampleID: id).map(\.common).contains("European Robin"))
        print("birds: unfiltered \(unfiltered.sorted()), London \(london.map { "\($0.common) x\($0.windows)" })")
    }
}
