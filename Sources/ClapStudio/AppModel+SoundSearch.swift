import ClapCore
import Foundation

extension AppModel {
    /// True when the search box can also match by meaning (the library was embedded with CLAP).
    var soundSearchActive: Bool {
        textSearchAvailable && !searchText.trimmingCharacters(in: .whitespaces).isEmpty
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
                textSearcher = TextSearcher(encoder: encoder)
                textSearchAvailable = true
                scheduleSoundSearch()
            }
        }
    }

    func scheduleSoundSearch() {
        soundSearchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard soundSearchActive, let store, let searcher = textSearcher else {
            if !soundScores.isEmpty { soundScores = [:]; soundScoresQuery = "" }
            return
        }
        soundSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let scores = await Task.detached { (try? searcher.scores(for: query, store: store)) ?? [:] }.value
            guard !Task.isCancelled else { return }
            soundScores = scores
            soundScoresQuery = query
            refilter()
        }
    }
}
