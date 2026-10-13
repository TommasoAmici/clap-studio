import ClapCore
import Foundation

/// Adjusting a search by example with words: "like this, but darker, no reverb".
extension AppModel {
    /// Phrases the menu offers to add or rule out.
    static let refinementSuggestions = ["dark", "bright", "warm", "punchy", "soft", "tight", "long", "distorted", "clean", "lo-fi",
                                        "vintage", "aggressive", "reverb", "noise"]

    var canRefineSearch: Bool { textSearchAvailable && exampleSearcher != nil }

    /// The words typed for the current search by example.
    var refinementText: String {
        get { exampleQuery?.refinement ?? "" }
        set {
            guard exampleQuery != nil, exampleQuery?.refinement != newValue else { return }
            exampleQuery?.refinement = newValue
            scheduleRefinement()
        }
    }

    /// Adds a phrase to the words, or rules it out ("no reverb").
    func addRefinement(_ phrase: String, negative: Bool) {
        let term = negative ? "no \(phrase)" : phrase
        let current = refinementText.trimmingCharacters(in: .whitespaces)
        let parsed = QueryRefinement.parse(current)
        if parsed.positives.contains(phrase) && !negative || parsed.negatives.contains(phrase) && negative { return }
        refinementText = current.isEmpty ? term : current + ", " + term
    }

    func scheduleRefinement(immediately: Bool = false) {
        refineTask?.cancel()
        guard let token = exampleQuery?.token else { return }
        refineTask = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(450)) }
            guard !Task.isCancelled, exampleQuery?.token == token else { return }
            await applyRefinement(token: token)
        }
    }

    private func applyRefinement(token: UUID) async {
        guard var query = exampleQuery, query.token == token, let searcher = exampleSearcher, let store else { return }
        let words = QueryRefinement.parse(query.refinement)
        // Back to the plain search when the words are gone.
        if words.isEmpty || textSearcher == nil {
            if let plain = query.plain { query.scores = plain.scores; query.segments = plain.segments; query.plain = nil }
            query.refining = false
            exampleQuery = query
            refilter()
            return
        }
        exampleQuery?.refining = true
        let textSearcher = self.textSearcher!
        let start = query.vector, reference = query.referenceID
        let outcome = await Task.detached { () -> (scores: [Int64: Float], segments: [Int64: SegmentMatch])? in
            guard let vector = start ?? reference.flatMap({ try? searcher.embedding(ofSample: $0) }).flatMap({ $0 }),
                  let base = try? searcher.results(forQuery: vector) else { return nil }
            var positives: [[Int64: Float]] = [], negatives: [[Int64: Float]] = []
            for phrase in words.positives { if let r = try? textSearcher.results(for: phrase, store: store) { positives.append(r.scores) } }
            for phrase in words.negatives { if let r = try? textSearcher.results(for: phrase, store: store) { negatives.append(r.scores) } }
            let combined = QueryRefinement.combine(base: base.scores, positives: positives, negatives: negatives)
            let top = combined.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(300)
            return (Dictionary(uniqueKeysWithValues: top.map { ($0.key, $0.value) }), base.segments)
        }.value
        // The user may have changed the words, or left the search, while this ran.
        guard !Task.isCancelled, var current = exampleQuery, current.token == token else { return }
        current.refining = false
        guard let outcome else { exampleQuery = current; return }
        if current.plain == nil { current.plain = (current.scores, current.segments) }
        var scores = outcome.scores
        if let reference = current.referenceID, let top = scores.values.max() { scores[reference] = top + 1 }
        current.scores = scores
        current.segments = outcome.segments.filter { scores[$0.key] != nil }
        exampleQuery = current
        refilter()
    }
}
