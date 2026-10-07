import Foundation
import Testing
@testable import ClapCore

@Suite struct AnalyzerTests {
    /// Fills a store with synthetic embeddings in `clusters` blobs (no audio needed).
    private func seed(_ store: LibraryStore, root: RootRecord, blobs: (vectors: [Float], labels: [Int]),
                      dim: Int, startingAt offset: Int = 0, version: String = "test-v1") throws {
        let n = blobs.labels.count
        let files = (0..<(offset + n)).map { ScannedFile(relPath: "s\($0).wav", size: 1, mtime: 1) }
        try store.sync(rootID: root.id, scanned: files) { _ in nil }
        let jobs = store.pendingJobs(limit: n + 10)
        let results = jobs.map { job -> IndexResult in
            let i = Int(job.url.lastPathComponent.dropFirst().dropLast(4))! - offset
            return .success(id: job.id, duration: 1, sampleRate: 44100, channels: 1,
                            embedding: Array(blobs.vectors[(i * dim)..<((i + 1) * dim)]),
                            fingerprint: nil, modelVersion: version)
        }
        try store.save(results: results)
    }

    @Test func fullRefreshPersistsAndWarmStartMatches() throws {
        let (store, dir) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/analysis")
        let blobs = makeBlobs(clusters: 4, perCluster: 60, dim: 32, spread: 0.3)
        try seed(store, root: root, blobs: blobs, dim: 32)

        let analyzer = LibraryAnalyzer(store: store)
        let first = try #require(try analyzer.refresh(modelVersion: "test-v1", clusterCount: 4))
        #expect(first.index.count == 240 && first.clusterCount == 4)

        // Relaunch: a fresh store on the same file loads identical data, no recompute.
        let reopened = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let warm = try #require(LibraryAnalyzer(store: reopened).loadSnapshot(modelVersion: "test-v1"))
        #expect(warm.index.ids == first.index.ids)
        #expect(warm.xy == first.xy)
        #expect(warm.clusters == first.clusters)
        #expect(warm.index.vectors == first.index.vectors)
    }

    @Test func newSamplesAreAddedWithoutMovingExistingOnes() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/analysis")
        let all = makeBlobs(clusters: 4, perCluster: 100, dim: 32, spread: 0.3)
        let first = (vectors: Array(all.vectors[0..<(390 * 32)]), labels: Array(all.labels[0..<390]))
        try seed(store, root: root, blobs: first, dim: 32)

        let analyzer = LibraryAnalyzer(store: store)
        let before = try #require(try analyzer.refresh(modelVersion: "test-v1", clusterCount: 4))

        let extra = (vectors: Array(all.vectors[(390 * 32)...]), labels: Array(all.labels[390...]))
        try seed(store, root: root, blobs: extra, dim: 32, startingAt: 390)
        let after = try #require(try analyzer.refresh(modelVersion: "test-v1"))

        #expect(after.index.count == 400)
        for (row, id) in before.index.ids.enumerated() {
            let r = try #require(after.index.row(forID: id))
            #expect(after.xy[r * 2] == before.xy[row * 2] && after.xy[r * 2 + 1] == before.xy[row * 2 + 1])
        }
    }

    @Test func reclusterChangesClusterCountOnly() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/analysis")
        try seed(store, root: root, blobs: makeBlobs(clusters: 6, perCluster: 40, dim: 32, spread: 0.3), dim: 32)
        let analyzer = LibraryAnalyzer(store: store)
        let base = try #require(try analyzer.refresh(modelVersion: "test-v1", clusterCount: 3))
        let more = try #require(try analyzer.recluster(modelVersion: "test-v1", k: 6))
        #expect(base.clusterCount == 3 && more.clusterCount == 6)
        #expect(more.xy == base.xy)
        #expect(analyzer.loadSnapshot(modelVersion: "test-v1")?.clusterCount == 6)
    }
}
