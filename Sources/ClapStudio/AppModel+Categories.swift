import ClapCore
import Foundation

extension AppModel {
    /// Names with at least one sample (as its category or a sound heard in it), in the canonical order, plus how many samples have none.
    func updateCategoryCounts() {
        var counts: [String: Int] = [:]
        for s in samples {
            // A recording counts for its category and for every sound heard in it.
            for c in Set([s.effectiveCategory].compactMap { $0 } + s.sounds) { counts[c, default: 0] += 1 }
        }
        categoryCounts = SoundCategories.names.compactMap { name in counts[name].map { (name: name, count: $0) } }
    }

    /// Moods with at least one sample, in the canonical order.
    func updateMoodCounts() {
        var counts: [String: Int] = [:]
        for s in samples { for mood in s.moods { counts[mood, default: 0] += 1 } }
        moodCounts = SoundMoods.names.compactMap { name in counts[name].map { (name: name, count: $0) } }
    }

    /// Something to classify: categories, moods or the sounds in field recordings are missing or were computed from other phrases or embeddings.
    nonisolated static func needsClassification(_ store: LibraryStore) -> Bool {
        store.categoryBacklog() > 0 || store.moodsAreStale() || store.soundsAreStale()
    }

    /// Sorts samples into categories and moods with CLAP (needs the text tower to embed the phrases).
    /// Runs on the indexing task, after embedding, and is fast enough not to need progress.
    nonisolated static func classifyLibrary(_ store: LibraryStore) {
        guard store.meta("model_version") == ClapEmbedder.versionTag, needsClassification(store),
              let encoder = try? ClapTextEncoder.load().get() else { return }
        if store.categoryBacklog() > 0, let categorizer = try? Categorizer(embed: encoder.embed) {
            _ = try? store.categorize(with: categorizer)
        }
        if store.moodsAreStale(), let scorer = try? MoodScorer(embed: encoder.embed) {
            _ = try? store.assignMoods(with: scorer)
        }
        // What each segment of a field recording sounds like (birds, water, ...).
        if store.soundsAreStale(), let segments = try? Categorizer(embed: encoder.embed, categories: SoundCategories.segmentVocabulary) {
            _ = try? store.labelSegments(with: segments)
        }
    }
}
