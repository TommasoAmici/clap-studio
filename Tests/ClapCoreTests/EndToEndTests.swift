import Foundation
import Testing
@testable import ClapCore

/// Indexes a folder of synthetic drum/bass/pad sounds through the real pipeline
/// (scan -> decode -> mel -> embed -> PCA -> clusters -> layout) and checks that
/// similarity search and clustering group sounds by type.
@Suite struct EndToEndTests {
    private static let classes = ["kick", "hat", "snare", "pad", "bass"]

    private func synth(_ kind: String, variant v: Double, rng: inout SplitMix64) -> (seconds: Double, f: (Double) -> Float) {
        let noise = (0..<80_000).map { _ in rng.nextFloat() * 2 - 1 }
        func n(_ t: Double) -> Float { noise[min(noise.count - 1, Int(t * 44_100))] }
        switch kind {
        case "kick": return (0.45, { t in Float(sin(2 * .pi * (50 + 110 * exp(-t * 25)) * (1 + 0.1 * v) * t)) * Float(exp(-t * 7)) })
        case "hat": return (0.12, { t in (n(t) - 0.95 * n(t + 0.00002)) * Float(exp(-t * (35 + 20 * v))) })
        case "snare": return (0.25, { t in (0.6 * n(t) + 0.4 * Float(sin(2 * .pi * (190 + 30 * v) * t))) * Float(exp(-t * 14)) })
        case "pad": return (1.6, { t in
            let env = Float(min(1, t / 0.6) * exp(-max(0, t - 1.0) * 3))
            return env * 0.4 * (Float(sin(2 * .pi * 220 * (1 + 0.05 * v) * t)) + Float(sin(2 * .pi * 330 * (1 + 0.05 * v) * t))) })
        default: return (0.8, { t in
            let f = 55 * (1 + 0.2 * v)
            return Float((2 * (t * f - floor(t * f + 0.5)))) * 0.6 * Float(exp(-t * 2)) })
        }
    }

    @Test func similarSoundsAreFoundAndClustered() async throws {
        try await runScenario(embedder: HandcraftedEmbedder(), minPrecision: 0.85)
    }

    /// Same scenario with the real CNN14 Core ML model; skipped when it has not been exported.
    @Test func neuralModelFindsAndClustersSoundTypes() async throws {
        guard case .success(let model) = CoreMLEmbedder.load() else { return }
        try await runScenario(embedder: model, minPrecision: 0.95)
    }

    /// Same scenario with LAION-CLAP; skipped when it has not been exported.
    @Test func clapModelFindsAndClustersSoundTypes() async throws {
        guard case .success(let model) = ClapEmbedder.load() else { return }
        let start = Date()
        try await runScenario(embedder: model, minPrecision: 0.9)
        print("CLAP scenario (150 files, 10 s windows): \(Date().timeIntervalSince(start)) s")
    }

    private func runScenario(embedder: EmbeddingProvider, minPrecision: Double) async throws {
        let dir = TestSupport.tempDir()
        var rng = SplitMix64(seed: 99)
        var labelByName: [String: String] = [:]
        for kind in Self.classes {
            for i in 0..<30 {
                let (seconds, f) = synth(kind, variant: Double(rng.nextFloat()), rng: &rng)
                let name = "\(kind)_\(i)"
                try writeTestWav(dir.appendingPathComponent("\(kind)s/\(name).wav"), seconds: seconds) { f($0) * 0.8 }
                labelByName[name] = kind
            }
        }

        let store = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        let done = await IndexingPipeline(store: store, embedder: embedder).run(onProgress: { _ in })
        #expect(done == 150)

        let analyzer = LibraryAnalyzer(store: store)
        let snapshot = try #require(try analyzer.refresh(modelVersion: embedder.version, clusterCount: 6))
        let names = Dictionary(uniqueKeysWithValues: store.loadSamples().map { ($0.id, $0.name) })
        func label(_ row: Int) -> String { labelByName[names[snapshot.index.ids[row]]!]! }

        // Nearest neighbours share the query's sound type.
        var hits = 0, total = 0
        for row in 0..<snapshot.index.count {
            for n in snapshot.index.similar(toRow: row, limit: 5) { total += 1; if label(n.row) == label(row) { hits += 1 } }
        }
        let precision = Double(hits) / Double(total)
        #expect(precision > minPrecision, "top-5 precision \(precision)")

        // Clusters are dominated by a single sound type.
        var pure = 0
        for c in 0..<6 {
            let members = (0..<snapshot.index.count).filter { snapshot.clusters[$0] == Int32(c) }
            guard !members.isEmpty else { continue }
            let top = Dictionary(grouping: members, by: label).values.map(\.count).max() ?? 0
            pure += top
        }
        #expect(Double(pure) / 150 > 0.85, "cluster purity \(Double(pure) / 150)")

        // Map positions exist for everything, are finite, and same-type points sit closer together.
        #expect(snapshot.xy.count == 300 && snapshot.xy.allSatisfy { $0.isFinite })
        var within: Float = 0, between: Float = 0, wc = 0, bc = 0
        for i in stride(from: 0, to: 150, by: 2) {
            for j in stride(from: 1, to: 150, by: 2) {
                let d = hypotf(snapshot.xy[i * 2] - snapshot.xy[j * 2], snapshot.xy[i * 2 + 1] - snapshot.xy[j * 2 + 1])
                if label(i) == label(j) { within += d; wc += 1 } else { between += d; bc += 1 }
            }
        }
        #expect(within / Float(wc) < 0.7 * between / Float(bc))

        // Relaunch: everything comes back from disk with no model work.
        let reopened = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        #expect(reopened.pendingCount() == 0)
        let warm = try #require(LibraryAnalyzer(store: reopened).loadSnapshot(modelVersion: embedder.version))
        #expect(warm.xy == snapshot.xy && warm.clusters == snapshot.clusters && warm.index.ids == snapshot.index.ids)
    }
}

extension EndToEndTests {
    /// Text queries must land near audio of the matching kind. Synthetic sounds are a weak proxy for real
    /// samples, so only the clearest contrasts are asserted.
    @Test func textSearchRanksMatchingSounds() async throws {
        guard case .success(let embedder) = ClapEmbedder.load(), case .success(let encoder) = ClapTextEncoder.load() else { return }
        let dir = TestSupport.tempDir()
        var rng = SplitMix64(seed: 5)
        var kind: [String: String] = [:]
        for k in ["kick", "hat", "pad"] {
            for i in 0..<12 {
                let (seconds, f) = synthForTextTest(k, variant: Double(rng.nextFloat()), rng: &rng)
                try writeTestWav(dir.appendingPathComponent("\(k)_\(i).wav"), seconds: seconds) { f($0) * 0.8 }
                kind["\(k)_\(i)"] = k
            }
        }
        let store = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        _ = await IndexingPipeline(store: store, embedder: embedder).run(onProgress: { _ in })
        let names = Dictionary(uniqueKeysWithValues: store.loadSamples().map { ($0.id, $0.name) })

        let searcher = TextSearcher(encoder: encoder)
        for (query, expected) in [("a sustained warm synth pad", "pad"), ("a short bright hi-hat", "hat")] {
            let top = try searcher.search(query, store: store, limit: 6).map { kind[names[$0.sampleID]!]! }
            let hits = top.filter { $0 == expected }.count
            print("text '\(query)' -> \(top)")
            #expect(hits >= 4, "'\(query)' returned \(top)")
        }
        #expect(try searcher.search("   ", store: store).isEmpty)

        // Zero-shot categories on the same sounds.
        let categorizer = try Categorizer(embed: encoder.embed)
        try store.setMeta("model_version", ClapEmbedder.versionTag)
        try store.categorize(with: categorizer)
        var correct = 0, total = 0
        let expectedCategory = ["kick": "Kick", "hat": "Hi-hat", "pad": "Pad"]
        var seen: [String: [String]] = [:]
        for s in store.loadSamples() {
            let k = kind[s.name]!
            seen[k, default: []].append(s.category ?? "-")
            total += 1
            if s.category == expectedCategory[k] { correct += 1 }
        }
        print("categories:", seen)
        #expect(Double(correct) / Double(total) >= 0.6, "categories \(seen)")
    }

    private func synthForTextTest(_ kind: String, variant v: Double, rng: inout SplitMix64) -> (Double, (Double) -> Float) {
        let noise = (0..<80_000).map { _ in rng.nextFloat() * 2 - 1 }
        func n(_ t: Double) -> Float { noise[min(noise.count - 1, Int(t * 44_100))] }
        switch kind {
        case "kick": return (0.45, { t in Float(sin(2 * .pi * (50 + 110 * exp(-t * 25)) * (1 + 0.1 * v) * t)) * Float(exp(-t * 7)) })
        case "hat": return (0.12, { t in (n(t) - 0.95 * n(t + 0.00002)) * Float(exp(-t * (35 + 20 * v))) })
        default: return (1.6, { t in
            let env = Float(min(1, t / 0.6) * exp(-max(0, t - 1.0) * 3))
            return env * 0.4 * (Float(sin(2 * .pi * 220 * (1 + 0.05 * v) * t)) + Float(sin(2 * .pi * 330 * (1 + 0.05 * v) * t))) })
        }
    }
}

extension EndToEndTests {
    @Test func fileOutsideTheLibraryFindsItsTwin() async throws {
        let choice = EmbedderFactory.make()
        let dir = TestSupport.tempDir(), outside = TestSupport.tempDir()
        var rng = SplitMix64(seed: 11)
        func tone(_ f: Double) -> (Double) -> Float { { t in Float(sin(2 * .pi * f * t)) * Float(exp(-t * 4)) * 0.7 } }
        func noise() -> (Double) -> Float {
            let n = (0..<44_100).map { _ in rng.nextFloat() * 2 - 1 }
            return { t in n[min(n.count - 1, Int(t * 44_100))] * Float(exp(-t * 30)) * 0.7 }
        }
        let low = tone(110), high = tone(3000), hat = noise(), query = tone(115)
        try writeTestWav(dir.appendingPathComponent("low.wav"), seconds: 0.8) { low($0) }
        try writeTestWav(dir.appendingPathComponent("high.wav"), seconds: 0.8) { high($0) }
        try writeTestWav(dir.appendingPathComponent("hat.wav"), seconds: 0.2) { hat($0) }
        try writeTestWav(outside.appendingPathComponent("query.wav"), seconds: 0.8) { query($0) }

        let store = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        _ = await IndexingPipeline(store: store, embedder: choice.provider).run(onProgress: { _ in })
        try store.setMeta("model_version", choice.provider.version)
        let names = Dictionary(uniqueKeysWithValues: store.loadSamples().map { ($0.id, $0.name) })

        let searcher = ExampleSearcher(store: store)
        let hits = try searcher.similar(to: outside.appendingPathComponent("query.wav"), limit: 3)
        #expect(hits.count == 3)
        #expect(names[hits[0].sampleID] == "low", "ranked \(hits.map { names[$0.sampleID] ?? "?" })")
        #expect(throws: ExampleSearchError.self) { try searcher.similar(to: outside.appendingPathComponent("notes.txt")) }
    }
}
