import Foundation
import Testing
@testable import ClapCore

@Suite struct MoodTests {
    /// Fake text tower: each phrase points along the axis named by its first word.
    private static let axes = ["dark": 0, "happy": 1, "epic": 2, "calm": 3]
    private static func fakeEmbed(_ text: String) -> [Float] {
        var v = [Float](repeating: 0.01, count: 4)
        for (word, axis) in axes where text.contains(word) { v[axis] = 1 }
        let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot()
        return v.map { $0 / n }
    }

    private static let moods: [(name: String, prompts: [String])] = [
        ("Dark", ["a dark sound"]), ("Happy", ["a happy sound"]), ("Epic", ["an epic sound"]),
    ]

    /// A library of `count` sounds that are mostly neutral, with the given sounds standing out.
    private static func library(count: Int, standouts: [Int: String]) -> [Float] {
        var flat: [Float] = []
        for i in 0..<count {
            var v = [Float](repeating: 0.5, count: 4)
            v[3] = 1                       // every sound is "calm", which no mood describes
            v[i % 3] += Float(i % 5) * 0.01
            if let word = standouts[i] { v = fakeEmbed(word) }
            let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot()
            flat += v.map { $0 / n }
        }
        return flat
    }

    @Test func soundsThatStandOutGetTheirMood() throws {
        let scorer = try MoodScorer(embed: { Self.fakeEmbed($0) }, moods: Self.moods)
        let flat = Self.library(count: 40, standouts: [0: "dark", 1: "happy", 2: "epic"])
        let result = scorer.assign(raw: scorer.rawScores(flat: flat, count: 40), count: 40)
        #expect(result[0].first.map { scorer.names[$0.mood] } == "Dark")
        #expect(result[1].first.map { scorer.names[$0.mood] } == "Happy")
        #expect(result[2].first.map { scorer.names[$0.mood] } == "Epic")
        #expect(result[10].isEmpty, "a typical sound has no mood that stands out")
    }

    @Test func aSoundKeepsAtMostThreeMoodsStrongestFirst() throws {
        let scorer = try MoodScorer(embed: { Self.fakeEmbed($0) }, moods: [
            ("A", ["dark"]), ("B", ["dark"]), ("C", ["dark"]), ("D", ["dark"]),
        ])
        var flat = Self.library(count: 40, standouts: [:])
        let loud = Self.fakeEmbed("dark")
        flat.replaceSubrange(0..<4, with: loud)
        let result = scorer.assign(raw: scorer.rawScores(flat: flat, count: 40), count: 40)
        #expect(result[0].count == SoundMoods.maxPerSound)
        #expect(result[0].map(\.z) == result[0].map(\.z).sorted(by: >))
    }

    @Test func tinyLibrariesGetNoMoods() throws {
        let scorer = try MoodScorer(embed: { Self.fakeEmbed($0) }, moods: Self.moods)
        let flat = Self.library(count: 10, standouts: [0: "dark"])
        let result = scorer.assign(raw: scorer.rawScores(flat: flat, count: 10), count: 10)
        #expect(result.allSatisfy { $0.isEmpty }, "an average over so few sounds means nothing")
    }

    @Test func moodsAreStoredAndRecomputedWhenTheLibraryChanges() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        let files = (0..<40).map { ScannedFile(relPath: "s\($0).wav", size: 1, mtime: 1) }
        _ = try store.sync(rootID: root.id, scanned: files) { $0 }
        let flat = Self.library(count: 40, standouts: [0: "dark"])
        let jobs = store.pendingJobs(limit: 40)
        let dim = 4
        // Jobs come in any order: give each sound the vector of the number in its file name.
        let results: [IndexResult] = jobs.map { job in
            let name = job.url.lastPathComponent
            let index = Int(name.dropFirst().dropLast(4))!
            return .success(id: job.id, duration: 1, sampleRate: 44100, channels: 1,
                            embedding: Array(flat[(index * dim)..<((index + 1) * dim)]), fingerprint: name,
                            modelVersion: ClapEmbedder.versionTag)
        }
        try store.save(results: results)

        let scorer = try MoodScorer(embed: { Self.fakeEmbed($0) }, moods: Self.moods)
        #expect(store.moodsAreStale())
        try store.assignMoods(with: scorer)
        #expect(!store.moodsAreStale())
        let dark = store.loadSamples().first { $0.relPath == "s0.wav" }
        #expect(dark?.moods == ["Dark"])
        #expect(store.loadSamples().first { $0.relPath == "s10.wav" }?.moods == [])

        try store.assignMoods(with: scorer)        // recomputing replaces, never duplicates
        #expect(store.loadSamples().first { $0.relPath == "s0.wav" }?.moods == ["Dark"])

        // The user's own moods win, are kept when moods are recomputed, and can be undone.
        let id = try #require(dark?.id)
        try store.setManualMoods([(id, ["Happy", "Dark"])])
        var edited = try #require(store.sample(id: id))
        #expect(edited.moods == ["Dark", "Happy"] && edited.moodsManual == ["Dark", "Happy"] && edited.moodsAuto == ["Dark"])
        try store.assignMoods(with: scorer)
        #expect(store.sample(id: id)?.moods == ["Dark", "Happy"])
        try store.setManualMoods([(id, [])])
        edited = try #require(store.sample(id: id))
        #expect(edited.moods == [] && edited.moodsManual == [], "none is a choice too")
        try store.setManualMoods([(id, nil)])
        edited = try #require(store.sample(id: id))
        #expect(edited.moods == ["Dark"] && edited.moodsManual == nil)

        _ = try store.sync(rootID: root.id, scanned: files + [ScannedFile(relPath: "new.wav", size: 1, mtime: 1)]) { $0 }
        let job = store.pendingJobs(limit: 1)[0]
        try store.save(results: [.success(id: job.id, duration: 1, sampleRate: 44100, channels: 1,
                                          embedding: Self.fakeEmbed("happy"), fingerprint: "new",
                                          modelVersion: ClapEmbedder.versionTag)])
        #expect(store.moodsAreStale(), "a new sound changes the library average, so moods are recomputed")
    }

    @Test func moodFilterMatchesAnyTickedMood() {
        var dark = SampleRecord(id: 1, rootID: 1, rootPath: "/", relPath: "a.wav", name: "a", ext: "wav", duration: 1,
                                sampleRate: 44100, channels: 1, size: 1, mtime: 0, status: .ok, useCount: 0,
                                lastUsed: nil, cueCount: 0)
        dark.moods = ["Dark", "Epic"]
        var filter = DescriptorFilter()
        #expect(filter.matches(dark) && !filter.isActive)
        filter.moods = ["Happy"]
        #expect(!filter.matches(dark) && filter.isActive)
        filter.moods = ["Happy", "Epic"]
        #expect(filter.matches(dark), "any of the ticked moods is enough")
        #expect(SoundMoods.sorted(["Groovy", "Dark", "Aggressive"]) == ["Aggressive", "Dark", "Groovy"])
    }
}
