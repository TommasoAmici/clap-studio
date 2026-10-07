import ClapCore
import Foundation

extension AppModel {
    /// True when the search box describes a sound instead of matching file names.
    var soundSearchActive: Bool {
        searchMode == .sound && textSearchAvailable && !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Loads the CLAP text encoder when the library was embedded with CLAP.
    func prepareTextSearch() {
        guard let store, store.meta("model_version") == ClapEmbedder.versionTag else {
            textSearcher = nil
            textSearchAvailable = false
            if searchMode == .sound { searchMode = .name }
            return
        }
        if textSearcher != nil { textSearchAvailable = true; return }
        Task {
            let encoder = await Task.detached { try? ClapTextEncoder.load().get() }.value
            if let encoder {
                textSearcher = TextSearcher(encoder: encoder)
                textSearchAvailable = true
            }
        }
    }

    func scheduleSoundSearch() {
        soundSearchTask?.cancel()
        guard soundSearchActive, let store, let searcher = textSearcher else {
            if !soundScores.isEmpty { soundScores = [:] }
            return
        }
        let query = searchText
        soundSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let hits = await Task.detached { (try? searcher.search(query, store: store)) ?? [] }.value
            guard !Task.isCancelled else { return }
            soundScores = Dictionary(uniqueKeysWithValues: hits.map { ($0.sampleID, $0.score) })
            refilter()
        }
    }
}
