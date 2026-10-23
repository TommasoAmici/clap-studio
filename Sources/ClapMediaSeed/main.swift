import AVFoundation
import ClapCore
import Foundation
import simd

/// Creates original, synthetic sounds and a cached demo library without needing a neural model.
enum MediaLibrary {
    static let rate = 44_100.0
    static let version = "media-demo-v1"
    static let families = ["Kick", "Snare", "Hi-hat", "Percussion", "Bass", "Keys", "Pad", "Synth"]
    static let titles = ["Studio Kick", "Dusty Snare", "Silver Hat", "Wood Percussion",
                         "Analog Bass", "Velvet Keys", "Cloud Pad", "Glass Synth"]

    static func seed(at directory: URL) async throws {
        let fm = FileManager.default
        // Refuse to replace a library: the capture script gives us a fresh temporary directory.
        let database = directory.appendingPathComponent("library.sqlite")
        let contents = fm.fileExists(atPath: directory.path)
            ? try fm.contentsOfDirectory(atPath: directory.path) : []
        guard contents.isEmpty else {
            throw NSError(domain: "ClapMediaSeed", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Choose a new or empty folder; this folder already has files."])
        }
        let samples = directory.appendingPathComponent("Studio Samples", isDirectory: true)
        try fm.createDirectory(at: samples, withIntermediateDirectories: true)
        let store = try LibraryStore(path: database.path)
        let root = try store.addRoot(path: samples.path)
        var descriptors: [String: SoundDescriptors] = [:]
        try await withThrowingTaskGroup(of: [String: SoundDescriptors].self) { group in
            for family in families.indices {
                group.addTask {
                    let analyzer = DescriptorAnalyzer()
                    let folder = samples.appendingPathComponent(families[family], isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    var measuredSounds: [String: SoundDescriptors] = [:]
                    for variation in 0..<48 {
                        try Task.checkCancellation()
                        let name = String(format: "%@ %02d", titles[family], variation + 1)
                        let audio = sound(family: family, variation: variation)
                        try write(audio, to: folder.appendingPathComponent(name + ".wav"))
                        var measured = analyzer.analyze(samples: audio, sampleRate: rate,
                                                        fileDuration: Double(audio.count) / rate)
                        if family >= 4 {
                            let pitch = frequency(variation) * (family == 5 || family == 7 ? 2 : 1)
                            measured.pitchHz = pitch
                            measured.keyName = NoteNames.name(forHz: pitch)
                        }
                        measuredSounds[name] = measured
                    }
                    return measuredSounds
                }
            }
            for try await measuredSounds in group {
                descriptors.merge(measuredSounds) { _, new in new }
            }
        }
        let files = FolderScanner.scan(root: samples).sorted { $0.relPath < $1.relPath }
        try store.sync(rootID: root.id, scanned: files) { path in
            FileFingerprint.compute(url: samples.appendingPathComponent(path))
        }
        var coordinates: [CoordRow] = []
        for sample in store.loadSamples() {
            let family = families.firstIndex(of: sample.folder)!
            let variation = Int(sample.name.suffix(2))! - 1
            let measured = descriptors[sample.name]!
            let angle = Double(family) * 2 * .pi / Double(families.count)
            let offset = Double(variation) * 2.39996323
            let radius = 0.07 + 0.21 * sqrt(Double(variation) / 48)
            let x = Float(0.65 * cos(angle) + radius * cos(offset))
            let y = Float(0.65 * sin(angle) + radius * sin(offset))
            // Deliberately fixed demonstration coordinates, not a claim of model classification.
            let unit = simd_normalize(SIMD4(x, y, Float(family) / 8, Float(variation) / 48))
            let vector = [unit.x, unit.y, unit.z, unit.w]
            try store.save(results: [.success(id: sample.id, duration: sample.duration == 0
                                              ? duration(family) : sample.duration,
                                              sampleRate: rate, channels: 1, embedding: vector,
                                              fingerprint: nil, modelVersion: version,
                                              descriptors: measured)])
            try store.setManualCategory(sampleID: sample.id, families[family])
            if variation % 8 == 0 { try store.setFavorite([sample.id], true) }
            try store.addTag(family < 4 ? "drum machine" : "analog", to: [sample.id])
            if variation % 3 == 0 { try store.addTag("warm", to: [sample.id]) }
            if family >= 4 && variation % 6 == 0 {
                try store.setManualMoods([(id: sample.id, moods: ["Dreamy", "Groovy"])])
            }
            for use in 0..<(variation % 5) {
                try store.recordGrab(sampleID: sample.id,
                                     at: Date(timeIntervalSince1970: 1_780_000_000 + Double(use)))
            }
            coordinates.append(CoordRow(sampleID: sample.id, pca: vector, cluster: family, x: x, y: y))
        }
        try store.saveCoords(coordinates)
        try store.setMeta("model_version", version)
        try store.setMeta("cluster_k", String(families.count))
        let records = store.loadSamples()
        for (name, categories) in [("Late Night", ["Bass", "Keys", "Pad"]),
                                    ("Drum Sketches", ["Kick", "Snare", "Hi-hat", "Percussion"])] {
            let collection = try store.createCollection(name: name, at: Date(timeIntervalSince1970: 1_780_000_000))
            try store.addToCollection(id: collection.id,
                                      sampleIDs: records.filter { categories.contains($0.effectiveCategory ?? "") }.prefix(24).map(\.id))
        }
        guard records.count == 384, records.allSatisfy({ $0.status == .ok && $0.duration > 0 }),
              LibraryAnalyzer(store: store).loadSnapshot(modelVersion: version)?.index.count == 384 else {
            throw NSError(domain: "ClapMediaSeed", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The demonstration library was not fully seeded."])
        }
        print("Seeded \(records.count) original sounds in \(directory.path)")
    }

    static func duration(_ family: Int) -> Double { family < 4 ? 0.65 : (family == 6 ? 2.8 : 1.4) }
    static func frequency(_ variation: Int) -> Double { 65.406 * pow(2, Double(variation % 12) / 12) }

    static func sound(family: Int, variation: Int) -> [Float] {
        let length = duration(family)
        var state = UInt64(family * 1000 + variation + 1)
        let frequency = frequency(variation)
        return (0..<Int(rate * length)).map { frame in
            let t = Double(frame) / rate
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let noise = Double(state >> 32) / Double(UInt32.max) * 2 - 1
            let fade = min(1, t / 0.004) * min(1, (length - t) / 0.025)
            let phase = 2 * Double.pi * frequency * t
            let value: Double
            switch family {
            case 0: value = sin(2 * .pi * (48 * t + 8 * (1 - exp(-t * 30)))) * exp(-t * 8)
            case 1: value = (noise * 0.7 + sin(2 * .pi * 180 * t) * 0.3) * exp(-t * 13)
            case 2: value = noise * sin(2 * .pi * 8_000 * t) * exp(-t * 32)
            case 3: value = (sin(2 * .pi * 430 * t) + noise * 0.25) * exp(-t * 18)
            case 4: value = (sin(phase) + sin(phase * 2) * 0.3) * exp(-t * 3)
            case 5: value = (sin(phase * 2) + sin(phase * 4.003) * 0.3) * exp(-t * 2.2)
            case 6: value = (sin(phase) + sin(phase * 1.006) * 0.4) * sin(.pi * t / length)
            default: value = (sin(phase * 2) + sin(phase * 3) * 0.35) * exp(-t * 4)
            }
            return Float(value * fade * (0.45 + Double(variation % 5) * 0.04))
        }
    }

    static func write(_ samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ])
        try file.write(from: buffer)
    }
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw NSError(domain: "ClapMediaSeed", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Usage: ClapMediaSeed NEW_DIRECTORY"])
    }
    try await MediaLibrary.seed(at: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
