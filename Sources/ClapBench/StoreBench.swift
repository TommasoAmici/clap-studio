import ClapCore
import Foundation

/// Measures the persistent paths a musician uses when opening and rescanning a library.
func benchmarkStore(count: Int, dimension: Int) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clap-bench-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("library.sqlite").path
    let store = try LibraryStore(path: path)
    let root = try store.addRoot(path: directory.appendingPathComponent("samples").path)
    let files = (0..<count).map { ScannedFile(relPath: "sample-\($0).wav", size: 100, mtime: 1) }
    try time("Library row sync") { _ = try store.sync(rootID: root.id, scanned: files) { _ in nil } }
    try time("Unchanged rescan") { _ = try store.sync(rootID: root.id, scanned: files) { _ in nil } }
    var vector = [Float](repeating: 0, count: dimension)
    vector[0] = 1
    // The app keeps original embeddings on disk and a 128-dimensional projection for search.
    try store.db.run("UPDATE samples SET status = 'ok', model_version = 'bench', embedding = ?",
                     [.blob(VectorCodec.encodeFloat16(vector))])
    let projectedDimension = min(128, dimension)
    let projection = Array(vector.prefix(projectedDimension))
    try store.db.run("""
        INSERT INTO sample_coords(sample_id, pca, cluster, x, y)
        SELECT id, ?, id % 16, (id % 400) * 0.005, (id / 400) * 0.005 FROM samples
        """, [.blob(VectorCodec.encodeFloat32(projection))])
    try time("Library reopen") {
        let reopened = try LibraryStore(path: path)
        precondition(reopened.loadSamples().count == count)
    }
    try time("Embedding streaming") {
        var streamed = 0
        try store.forEachEmbeddingChunk(modelVersion: "bench") { _, _, rows in streamed += rows }
        precondition(streamed == count)
    }
    time("Embedding width lookup") {
        precondition(store.embeddedDimension(modelVersion: "bench") == dimension)
    }
    time("Cached analysis reload") {
        precondition(LibraryAnalyzer(store: store).loadSnapshot(modelVersion: "bench")?.index.count == count)
    }
}
