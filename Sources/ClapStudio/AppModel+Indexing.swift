import ClapCore
import Foundation

extension AppModel {
    /// Scans every root (incremental), embeds new or changed files, then refreshes the map.
    /// Safe to call repeatedly; it resumes from whatever is still pending in the database.
    func startIndexing() {
        guard !isIndexing, let store, let analyzer else { return }
        isIndexing = true
        cancelToken = CancelToken()
        let token = cancelToken
        let roots = self.roots

        Task {
            statusMessage = "Loading embedding model"
            let choice = await Task.detached { EmbedderFactory.make() }.value
            usingFallbackModel = choice.isFallback
            modelNote = choice.note

            // Never replace expensive neural embeddings with the DSP fallback just
            // because the model file went missing.
            let storedVersion = store.meta("model_version")
            let keepStored = choice.isFallback && storedVersion != nil && storedVersion != choice.provider.version
            let version = keepStored ? storedVersion! : choice.provider.version
            embedder = keepStored ? nil : choice.provider
            if keepStored {
                modelNote = "Embedding model not found; using existing embeddings. New samples will be embedded once the model is available."
            }

            statusMessage = "Scanning folders"
            for root in roots where !token.isCancelled {
                await Task.detached { Self.syncRoot(root, store: store, token: token) }.value
            }
            if !keepStored { _ = try? store.markStale(currentModelVersion: version) }
            reloadSamples()

            if let embedder, store.pendingCount() > 0, !token.isCancelled {
                statusMessage = "Indexing samples"
                let pipeline = IndexingPipeline(store: store, embedder: embedder)
                var lastReload = Date()
                await pipeline.run(onProgress: { [weak self] p in
                    Task { @MainActor in
                        self?.progress = p
                        if Date().timeIntervalSince(lastReload) > 5 { lastReload = Date(); self?.reloadSamples() }
                    }
                }, isCancelled: { token.isCancelled })
                try? store.setMeta("model_version", version)
            }
            progress = nil

            // Libraries indexed before descriptors existed: measure them without re-embedding.
            if store.descriptorBacklog() > 0, !token.isCancelled {
                await DescriptorBackfill(store: store).run(onProgress: { [weak self] done, total in
                    Task { @MainActor in self?.statusMessage = "Measuring sounds (\(done)/\(total))" }
                }, isCancelled: { token.isCancelled })
            }
            if store.categoryBacklog() > 0, !token.isCancelled {
                statusMessage = "Sorting sounds into categories"
                await Task.detached { Self.categorizeLibrary(store) }.value
            }
            failedCount = store.failedCount()
            reloadSamples()

            if !token.isCancelled { await runAnalysis(modelVersion: version, force: false, analyzer: analyzer) }
            statusMessage = ""
            isIndexing = false
        }
    }

    func cancelIndexing() { cancelToken.cancel() }

    nonisolated static func syncRoot(_ root: RootRecord, store: LibraryStore, token: CancelToken) {
        let rootURL = URL(fileURLWithPath: root.path)
        let files = FolderScanner.scan(root: rootURL, isCancelled: { token.isCancelled })
        guard !token.isCancelled else { return }
        _ = try? store.sync(rootID: root.id, scanned: files) { rel in
            FileFingerprint.compute(url: rootURL.appendingPathComponent(rel))
        }
    }

    func runAnalysis(modelVersion: String, force: Bool, analyzer: LibraryAnalyzer) async {
        guard let store else { return }
        statusMessage = "Analyzing library"
        let k = store.meta("cluster_k").flatMap(Int.init)
        let report: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor in self?.statusMessage = message }
        }
        do {
            let snap = try await Task.detached {
                try analyzer.refresh(modelVersion: modelVersion, force: force, clusterCount: k, status: report)
            }.value
            snapshot = snap
            if let snap { clusterCount = snap.clusterCount }
            afterSnapshotChange()
        } catch {
            errorMessage = "Analysis failed: \(error)"
        }
    }

    /// Rebuild PCA, clusters and the 2D layout from scratch.
    func relayout() {
        guard !isIndexing, let analyzer, let version = store?.meta("model_version") else { return }
        isIndexing = true
        Task {
            await runAnalysis(modelVersion: version, force: true, analyzer: analyzer)
            statusMessage = ""
            isIndexing = false
        }
    }

    func setClusterCount(_ k: Int) {
        guard let analyzer, let store, let version = store.meta("model_version"), k != clusterCount else { return }
        clusterCount = k
        try? store.setMeta("cluster_k", String(k))
        Task {
            if let snap = try? await Task.detached(operation: { try analyzer.recluster(modelVersion: version, k: k) }).value {
                snapshot = snap
                afterSnapshotChange(layoutChanged: false)
            }
        }
    }

    /// `layoutChanged` is false when only cluster colours changed, so the map keeps its zoom and pan.
    func afterSnapshotChange(layoutChanged: Bool = true) {
        if layoutChanged { mapVersion += 1 }
        clusterVersion += 1
        textSearcher?.invalidate()
        exampleSearcher?.invalidate()
        prepareTextSearch()
        hoverRow = nil
        buildClusterInfo()
        if let id = selectedID { updateSimilar(for: id) }
    }

    private func buildClusterInfo() {
        guard let snap = snapshot else { clusterInfo = []; return }
        var counts = [Int: Int](), folders = [Int: [String: Int]]()
        for (row, cluster) in snap.clusters.enumerated() {
            let c = Int(cluster)
            counts[c, default: 0] += 1
            if let s = sampleByID[snap.index.ids[row]] {
                let name = s.folder.isEmpty ? (s.rootPath as NSString).lastPathComponent
                                            : (s.folder as NSString).lastPathComponent
                folders[c, default: [:]][name, default: 0] += 1
            }
        }
        clusterInfo = counts.keys.sorted().map { c in
            ClusterInfo(id: c, count: counts[c] ?? 0, label: folders[c]?.max { $0.value < $1.value }?.key ?? "Cluster \(c + 1)")
        }
    }
}
