import ClapCore
import Foundation

extension AppModel {
    /// True when the search box can also match by meaning (the library was embedded with CLAP).
    var soundSearchActive: Bool {
        textSearchAvailable && !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True from the first keystroke until the semantic results for the current text have arrived,
    /// so the UI can show progress instead of an empty or partial list.
    var searchPending: Bool {
        soundSearchActive && soundScoresQuery != searchText.trimmingCharacters(in: .whitespaces)
    }

    /// Loads the CLAP text encoder when the library was embedded with CLAP.
    func prepareTextSearch() {
        guard let store, store.meta("model_version") == ClapEmbedder.versionTag else {
            textSearcher = nil
            textSearchAvailable = false
            return
        }
        if textSearcher != nil { textSearchAvailable = true; return }
        Task {
            let encoder = await Task.detached { try? ClapTextEncoder.load().get() }.value
            if let encoder {
                textSearcher = TextSearcher(encoder: encoder, segments: segmentCache)
                textSearchAvailable = true
                scheduleSoundSearch()
            }
        }
    }

    func scheduleSoundSearch() {
        soundSearchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard soundSearchActive, let store, let searcher = textSearcher else {
            if !soundScores.isEmpty { soundScores = [:]; soundSegments = [:]; soundScoresQuery = "" }
            return
        }
        soundSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let result = await Task.detached { (try? searcher.results(for: query, store: store)) ?? TextSearchResult(scores: [:], segments: [:]) }.value
            guard !Task.isCancelled else { return }
            soundScores = result.scores
            soundSegments = result.segments
            soundScoresQuery = query
            refilter()
        }
    }
}
