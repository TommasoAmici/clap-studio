import ClapCore
import Foundation

/// What files say about themselves: shown in the properties, searched with the search box, turned into tags on
/// request, and the category and tags written back into WAV files.
extension AppModel {
    func fileMetadata(for id: Int64) -> FileMetadata? { store?.fileMetadata(sampleID: id) }

    /// Samples whose file metadata mentions the search text. The answer is kept while the text stays the same.
    func filesMentioning(_ query: String) -> Set<Int64> {
        if let cached = fileInfoSearch, cached.query == query, cached.revision == fileInfoRevision { return cached.ids }
        let ids = store?.samplesWithFileMetadata(matching: query) ?? []
        fileInfoSearch = (query, fileInfoRevision, ids)
        return ids
    }

    // MARK: keywords as tags

    /// Adds the keywords found in the files as tags: one undo step for the lot.
    func importFileKeywords(_ ids: [Int64]) {
        guard let store else { return }
        let found = store.fileKeywords(sampleIDs: ids)
        var byTag: [String: (tag: String, ids: [Int64])] = [:]
        for (id, words) in found {
            let have = Set(sampleByID[id]?.tags.map { $0.lowercased() } ?? [])
            for word in words {
                let tag = LibraryStore.cleanTag(word)
                guard !tag.isEmpty, !have.contains(tag.lowercased()) else { continue }
                byTag[tag.lowercased(), default: (tag, [])].ids.append(id)
            }
        }
        let additions = byTag.values.sorted { $0.tag < $1.tag }
        guard !additions.isEmpty else {
            statusMessage = found.isEmpty ? "These files carry no keywords." : "Their keywords are already tags."
            return
        }
        let count = Set(additions.flatMap(\.ids)).count
        record(LibraryEdit(name: "Tags from File Keywords",
                           undo: { [unowned self] in for a in additions { applyTag(a.tag, to: a.ids, add: false) } },
                           redo: { [unowned self] in for a in additions { applyTag(a.tag, to: a.ids, add: true) } }))
        for a in additions { applyTag(a.tag, to: a.ids, add: true) }
        statusMessage = "Added \(additions.count) tags to \(samplesPhrase(count))"
    }

    // MARK: writing into files

    /// WAV files off a USB drive (those are never changed) can carry tags.
    func canWriteTags(_ sample: SampleRecord) -> Bool {
        CueFileSync.canStoreCues(ext: sample.ext) && !isOnUsb(sample.id)
    }

    func writeTagsToFiles(_ ids: [Int64], keepBackup: Bool) {
        guard let store else { return }
        let samples = ids.compactMap { sampleByID[$0] }.filter(canWriteTags)
        guard !samples.isEmpty else { return }
        statusMessage = "Writing tags into files"
        Task {
            let outcome = await Task.detached { () -> (written: [SampleRecord], failures: [String]) in
                var written: [SampleRecord] = [], failures: [String] = []
                for sample in samples {
                    do { try store.writeTagsToFile(sample: sample, keepBackup: keepBackup); written.append(sample) }
                    catch { failures.append("\(sample.name): \(error)") }
                }
                return (written, failures)
            }.value
            for sample in outcome.written {
                if let fresh = store.sample(id: sample.id) { mutate(sample.id) { $0.size = fresh.size; $0.mtime = fresh.mtime } }
            }
            fileInfoRevision += 1
            statusMessage = outcome.failures.isEmpty ? "Wrote tags into \(outcome.written.count) \(outcome.written.count == 1 ? "file" : "files")" : ""
            if let first = outcome.failures.first {
                errorMessage = "Could not write \(outcome.failures.count) of \(samples.count) files. " + first
            }
        }
    }
}
