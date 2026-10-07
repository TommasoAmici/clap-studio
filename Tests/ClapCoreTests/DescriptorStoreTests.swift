import Foundation
import Testing
@testable import ClapCore

@Suite struct DescriptorStoreTests {
    private func library() async throws -> (LibraryStore, URL) {
        let dir = TestSupport.tempDir()
        try writeTestWav(dir.appendingPathComponent("tone.wav"), seconds: 1) { Float(0.5 * sin(2 * .pi * 440 * $0)) }
        let beat = 0.5
        try writeTestWav(dir.appendingPathComponent("loop.wav"), seconds: beat * 8) { t in
            let s = t.truncatingRemainder(dividingBy: beat)
            return Float(0.8 * sin(2 * .pi * (55 + 90 * exp(-s * 30)) * s) * exp(-s * 9))
        }
        let store = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        return (store, dir)
    }

    @Test func indexingStoresDescriptors() async throws {
        let (store, _) = try await library()
        await IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 1).run(onProgress: { _ in })
        let samples = Dictionary(uniqueKeysWithValues: store.loadSamples().map { ($0.name, $0) })
        let tone = try #require(samples["tone"]), loop = try #require(samples["loop"])
        #expect(tone.isLoop == false && tone.keyName == "A4")
        #expect(abs((tone.pitchHz ?? 0) - 440) < 5)
        #expect(abs((tone.peakDB ?? 0) - (-6)) < 0.5)
        #expect(loop.isLoop == true)
        #expect(abs((loop.bpm ?? 0) - 120) < 3, "bpm \(loop.bpm ?? 0)")
        #expect(store.descriptorBacklog() == 0)
    }

    @Test func backfillMeasuresSamplesIndexedEarlier() async throws {
        let (store, _) = try await library()
        await IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 1).run(onProgress: { _ in })
        try store.db.run("UPDATE samples SET desc_version = 0, bpm = NULL, key_name = NULL, loudness = NULL")
        #expect(store.descriptorBacklog() == 2 && store.loadSamples().allSatisfy { $0.loudnessDB == nil })

        let done = await DescriptorBackfill(store: store, workers: 2).run(onProgress: { _, _ in })
        #expect(done == 2 && store.descriptorBacklog() == 0)
        #expect(store.loadSamples().allSatisfy { $0.loudnessDB != nil })
    }

    @Test func manualBPMOverridesDetection() async throws {
        let (store, _) = try await library()
        await IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 1).run(onProgress: { _ in })
        let loop = try #require(store.loadSamples().first { $0.name == "loop" })
        try store.setManualBPM(sampleID: loop.id, 95)
        #expect(store.sample(id: loop.id)?.effectiveBPM == 95)
        try store.setManualBPM(sampleID: loop.id, nil)
        #expect(abs((store.sample(id: loop.id)?.effectiveBPM ?? 0) - 120) < 3)
    }

    @Test func changedFilesAreRemeasured() async throws {
        let (store, dir) = try await library()
        await IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 1).run(onProgress: { _ in })
        try writeTestWav(dir.appendingPathComponent("tone.wav"), seconds: 1.2) { Float(0.5 * sin(2 * .pi * 220 * $0)) }
        let root = try #require(store.roots().first)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        #expect(store.pendingCount() == 1)
        await IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 1).run(onProgress: { _ in })
        let tone = try #require(store.loadSamples().first { $0.name == "tone" })
        #expect(abs((tone.pitchHz ?? 0) - 220) < 3, "re-measured after the file changed")
        #expect(store.descriptorBacklog() == 0)
    }

    @Test func migrationFromV1KeepsData() throws {
        let dir = TestSupport.tempDir()
        let path = dir.appendingPathComponent("old.sqlite").path
        let raw = try SQLiteDB(path: path)
        try raw.exec("""
            CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
            CREATE TABLE roots(id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, last_scan REAL);
            CREATE TABLE samples(id INTEGER PRIMARY KEY, root_id INTEGER NOT NULL, rel_path TEXT NOT NULL, name TEXT NOT NULL,
                ext TEXT NOT NULL, duration REAL, sample_rate REAL, channels INTEGER, size INTEGER NOT NULL, mtime REAL NOT NULL,
                fingerprint TEXT, status TEXT NOT NULL DEFAULT 'pending', error TEXT, indexed_at REAL, model_version TEXT,
                embedding BLOB, cues_dirty INTEGER NOT NULL DEFAULT 0, UNIQUE(root_id, rel_path));
            CREATE TABLE usage_events(id INTEGER PRIMARY KEY, sample_id INTEGER NOT NULL, ts REAL NOT NULL);
            CREATE TABLE cue_points(id INTEGER PRIMARY KEY, sample_id INTEGER NOT NULL, position_frames INTEGER NOT NULL,
                label TEXT NOT NULL DEFAULT '', source TEXT NOT NULL, file_synced INTEGER NOT NULL DEFAULT 0);
            INSERT INTO roots(id, path) VALUES(1, '/tmp/x');
            INSERT INTO samples(root_id, rel_path, name, ext, size, mtime, status) VALUES(1, 'a.wav', 'a', 'wav', 10, 1, 'ok');
            PRAGMA user_version = 1;
            """)
        let store = try LibraryStore(path: path)
        let sample = try #require(store.loadSamples().first)
        #expect(sample.name == "a" && sample.loudnessDB == nil && !sample.favorite && !sample.hidden)
        #expect(store.descriptorBacklog() == 1)
    }
}
