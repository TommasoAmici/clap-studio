import ClapCore
import Foundation

/// A pretend USB stick made only from the demo library's original sounds.
enum MediaSquid {
    static func seed(in directory: URL, samples: [SampleRecord]) throws {
        let volume = directory.appendingPathComponent("Squid Demo", isDirectory: true)
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        func source(family: Int, variation: Int) throws -> SquidSource {
            let name = String(format: "%@ %02d", MediaLibrary.titles[family], variation + 1)
            guard let sample = samples.first(where: { $0.name == name }) else {
                throw SquidExportError.missing("The demo sound \(name)")
            }
            return SquidSource(file: sample.url, name: sample.name, category: sample.effectiveCategory, matchLevel: true)
        }
        for (number, name, count) in [(1, "STUDIO", 8), (2, "DUSTY", 6), (3, "GLASS", 8), (4, "NIGHT", 4)] {
            let sources = try (0..<count).map { try source(family: $0, variation: (number - 1) * 8) }
            try SquidExporter.export(SquidBankRequest(set: "Studio", number: number, name: name,
                                                      slots: sources.map { Optional($0) }), toVolume: volume)
        }
        let live = try (0..<4).map { try source(family: $0, variation: 36) }
        try SquidExporter.export(SquidBankRequest(set: "Live", number: 1, name: "LIVEKIT",
                                                  slots: live.map { Optional($0) }), toVolume: volume)
        for (folder, family) in [("Drums/Kicks", 0), ("Drums/Snares", 1), ("Percussion", 3), ("Textures", 6)] {
            try SquidExporter.exportToPool((0..<6).map { try source(family: family, variation: $0 + 8) },
                                           subfolder: folder, toVolume: volume)
        }
        let contents = SquidStick.read(volume: volume)
        let files = FolderScanner.scan(root: SquidStick.rootURL(volume: volume))
        guard contents.set(named: "Studio")?.banks.map(\.filledSlots) == [8, 6, 8, 4],
              contents.set(named: "Live")?.banks.first?.filledSlots == 4,
              contents.poolFolderPaths.count == 5, files.count == 54,
              files.allSatisfy({ WavInfo.category(of: SquidStick.rootURL(volume: volume).appendingPathComponent($0.relPath)) != nil }) else {
            throw SquidExportError.failed("The demonstration stick was not fully seeded.")
        }
        try cacheMeasurements(volume: volume, files: files)
        try Data("media-squid-v1\n".utf8).write(to: volume.appendingPathComponent(".clap-media-fixture"))
        print("Seeded \(files.count) original sounds on the demonstration Squid stick")
    }

    /// Measure once in the release seeder: doing this in each debug capture exceeds its time limit.
    private static func cacheMeasurements(volume: URL, files: [ScannedFile]) throws {
        let rootURL = SquidStick.rootURL(volume: volume)
        let store = try LibraryStore(path: volume.appendingPathComponent(".clap-media.sqlite").path)
        let root = try store.addRoot(path: rootURL.path)
        try store.sync(rootID: root.id, scanned: files) { path in
            FileFingerprint.compute(url: rootURL.appendingPathComponent(path))
        }
        let analyzer = DescriptorAnalyzer()
        for sample in store.loadSamples() {
            let audio = try AudioDecoder.decodeForAnalysis(url: sample.url, sampleRate: SquidLayout.sampleRate)
            let measured = analyzer.analyze(samples: audio.samples, sampleRate: SquidLayout.sampleRate,
                                            fileDuration: audio.duration)
            try store.save(results: [.success(id: sample.id, duration: audio.duration, sampleRate: audio.sampleRate,
                                              channels: audio.channels, embedding: [1, 0, 0, 0], fingerprint: nil,
                                              modelVersion: "media-squid-v1", descriptors: measured)])
            try store.setManualCategory(sampleID: sample.id, WavInfo.category(of: sample.url))
        }
        guard store.loadSamples().count == files.count,
              store.loadSamples().allSatisfy({ $0.status == .ok && $0.duration > 0 && $0.loudnessDB != nil }) else {
            throw SquidExportError.failed("The demonstration stick's sound measurements were not fully cached.")
        }
        try store.setMeta("media_fixture_version", "media-squid-v1")
    }
}
