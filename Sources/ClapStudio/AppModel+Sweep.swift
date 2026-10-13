import ClapCore
import Foundation

extension AppModel {
    // MARK: keyboard sweep

    /// Steps through the sounds most like the one you started from (→ further away, ← back), previewing each.
    /// The list is fixed when the sweep starts, so you can walk away from the start and come back to it.
    func sweep(_ step: Int) {
        guard let current = selectedID else { return }
        if !sweepList.contains(current) { startSweep(from: current) }
        guard let position = sweepList.firstIndex(of: current) else { return }
        let target = min(max(position + step, 0), sweepList.count - 1)
        guard target != position else { return }
        select(sweepList[target], play: true, keepSweep: true)
    }

    private func startSweep(from id: Int64) {
        guard let snap = snapshot, let reference = sampleByID[id] else { sweepList = []; return }
        let neighbours = AspectSimilarity.rank(reference: reference, index: snap.index, weights: aspectWeights, limit: 100) { [sampleByID] in sampleByID[$0] }
            .map { snap.index.ids[$0.row] }
        sweepList = [id] + neighbours.filter { sampleByID[$0]?.hidden == false }
    }

    var sweepPosition: (index: Int, count: Int)? {
        guard let id = selectedID, let i = sweepList.firstIndex(of: id), sweepList.count > 1 else { return nil }
        return (i, sweepList.count - 1)
    }

    // MARK: query by example

    /// Ranks the library by similarity to a file that need not be part of it (for example one dragged in from Finder).
    /// `cleanUp` deletes the file afterwards (for a temporary recording).
    func findSimilar(toFileAt url: URL, name: String? = nil, cleanUp: Bool = false) {
        guard let searcher = exampleSearcher else { return }
        errorMessage = nil
        Task {
            defer { if cleanUp { try? FileManager.default.removeItem(at: url) } }
            do {
                let hits = try await Task.detached { try searcher.similar(to: url, limit: 100) }.value
                exampleQuery = ExampleQuery(name: name ?? url.lastPathComponent,
                                            scores: Dictionary(hits.map { ($0.sampleID, $0.score) }, uniquingKeysWith: max),
                                            segments: Dictionary(hits.compactMap { hit in hit.segment.map { (hit.sampleID, $0) } },
                                                                 uniquingKeysWith: { first, _ in first }))
                searchText = ""
                refilter()
            } catch {
                errorMessage = "Could not find similar sounds: \(error)"
            }
        }
    }

    func clearExample() {
        guard exampleQuery != nil else { return }
        exampleQuery = nil
        refilter()
    }
}

struct ExampleQuery {
    let name: String
    var scores: [Int64: Float]
    /// Where in each field recording the match is.
    var segments: [Int64: SegmentMatch] = [:]
    /// Set when the query is a library sample (not a dropped file), so it can follow the similarity weights.
    var referenceID: Int64?
}
