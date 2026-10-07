import ClapCore
import Foundation

extension AppModel {
    /// Names with at least one sample, in the canonical order, plus how many samples have none.
    func updateCategoryCounts() {
        var counts: [String: Int] = [:]
        for s in samples { if let c = s.effectiveCategory { counts[c, default: 0] += 1 } }
        categoryCounts = SoundCategories.names.compactMap { name in counts[name].map { (name: name, count: $0) } }
    }

    /// Classifies samples with CLAP (needs the text tower to embed the category phrases).
    /// Runs on the indexing task, after embedding, and is fast enough not to need progress.
    nonisolated static func categorizeLibrary(_ store: LibraryStore) {
        guard store.meta("model_version") == ClapEmbedder.versionTag, store.categoryBacklog() > 0,
              let encoder = try? ClapTextEncoder.load().get(),
              let categorizer = try? Categorizer(embed: encoder.embed) else { return }
        _ = try? store.categorize(with: categorizer)
    }
}
