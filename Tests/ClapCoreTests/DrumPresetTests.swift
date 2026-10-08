import Foundation
import Testing
@testable import ClapCore

@Suite struct DrumPresetTests {
    @Test func everyPresetIsWellFormed() {
        #expect(DrumPreset.all.count >= 6)
        #expect(Set(DrumPreset.all.map(\.id)).count == DrumPreset.all.count, "ids are unique")
        for preset in DrumPreset.all {
            #expect((60...200).contains(preset.bpm), "\(preset.name) has a plausible tempo")
            #expect((50...75).contains(preset.swingPercent))
            for (category, lines) in preset.rhythms {
                #expect(!lines.isEmpty, "\(preset.name) \(category)")
                for line in lines { #expect(line.count == DrumPattern.stepCount, "\(preset.name) \(category) '\(line)' has 16 steps") }
            }
            #expect(preset.hits(for: "Kick").contains(true) && preset.hits(for: "Snare").contains(true))
        }
    }

    @Test func rhythmsFollowTheCategory() throws {
        let dnb = try #require(DrumPreset.preset(id: "dnb"))
        #expect(dnb.bpm == 174)
        #expect(dnb.hits(for: "Snare").indices.filter { dnb.hits(for: "Snare")[$0] } == [4, 12])
        #expect(dnb.hits(for: "Clap") == dnb.hits(for: "Snare"), "a clap is the backbeat too")
        #expect(!dnb.hits(for: "Bass").contains(true) && !dnb.hits(for: nil).contains(true), "no part for other sounds")
        #expect(dnb.hits(for: "Hi-hat", occurrence: 0) != dnb.hits(for: "Hi-hat", occurrence: 1), "a second hat plays another line")
        #expect(dnb.hits(for: "Hi-hat", occurrence: 2) == dnb.hits(for: "Hi-hat", occurrence: 0), "lines wrap around")
        #expect(DrumPreset.preset(id: "nope") == nil && DrumPreset.preset(id: nil) == nil)
    }

    @Test func applyingAPresetKeepsSoundsAndMixer() throws {
        let techno = try #require(DrumPreset.preset(id: "techno"))
        var pattern = DrumPattern()
        pattern.addTrack(sampleID: 1, label: "Kick", category: "Kick")
        pattern.addTrack(sampleID: 2, label: "Hi-hat", category: "Hi-hat")
        pattern.addTrack(sampleID: 3, label: "Hi-hat", category: "Hi-hat")
        pattern.addTrack(sampleID: 4, label: "Bass", category: "Bass")
        pattern.tracks[0].volume = 0.4; pattern.tracks[0].muted = true
        pattern.swing = 0.3
        pattern.apply(techno)
        #expect(pattern.tracks.map(\.sampleID) == [1, 2, 3, 4])
        #expect(pattern.tracks[0].volume == 0.4 && pattern.tracks[0].muted)
        #expect(pattern.tracks[0].hits == techno.hits(for: "Kick"))
        #expect(pattern.tracks[1].hits == techno.hits(for: "Hi-hat", occurrence: 0))
        #expect(pattern.tracks[2].hits == techno.hits(for: "Hi-hat", occurrence: 1))
        #expect(!pattern.tracks[3].hits.contains(true))
        #expect(pattern.swing == techno.swing)
    }

    @Test func newTracksTakeThePresetRhythm() throws {
        let trap = try #require(DrumPreset.preset(id: "trap"))
        var pattern = DrumPattern()
        pattern.addTrack(sampleID: 1, label: "Snare", category: "Snare", preset: trap)
        pattern.addTrack(sampleID: 2, label: "Hi-hat", category: "Hi-hat", preset: trap)
        pattern.addTrack(sampleID: 3, label: "Hi-hat", category: "Hi-hat", preset: trap)
        #expect(pattern.tracks[0].hits.indices.filter { pattern.tracks[0].hits[$0] } == [8], "trap snare is half-time")
        #expect(pattern.tracks[2].hits == trap.hits(for: "Hi-hat", occurrence: 1))
        pattern.addTrack(sampleID: 4, label: "Kick", category: "Kick")
        #expect(pattern.tracks[3].hits == DrumStarter.hits(for: "Kick"), "no preset: plain starter")
    }

    @Test func aPatternCanBeSavedAsAGroove() throws {
        var pattern = DrumPattern()
        pattern.addTrack(sampleID: 1, label: "Kick", category: "Kick", preset: nil)
        pattern.addTrack(sampleID: 2, label: "Hi-hat", category: "Hi-hat", preset: nil)
        pattern.addTrack(sampleID: 3, label: "Hi-hat", category: "Hi-hat", starter: false)
        pattern.toggle(track: 2, step: 3)
        pattern.swing = 0.2
        let saved = try #require(pattern.makePreset(name: "  My\ngroove  ", bpm: 101))
        #expect(saved.name == "My groove" && saved.isUser && saved.bpm == 101 && saved.id.hasPrefix("user."))
        #expect(abs(saved.swingPercent - 60) < 1e-9)

        // Applied to another kit it brings the same rhythms back, per category and in track order.
        var other = DrumPattern()
        other.addTrack(sampleID: 9, label: "Kick", category: "Kick", starter: false)
        other.addTrack(sampleID: 8, label: "Hi-hat", category: "Hi-hat", starter: false)
        other.addTrack(sampleID: 7, label: "Hi-hat", category: "Hi-hat", starter: false)
        other.apply(saved)
        #expect(other.tracks.map(\.hits) == pattern.tracks.map(\.hits))
        #expect(other.swing == pattern.swing)

        // Survives storage.
        let decoded = try JSONDecoder().decode([DrumPreset].self, from: JSONEncoder().encode([saved]))
        #expect(decoded == [saved])
        #expect(DrumPreset.preset(id: saved.id, among: decoded) == saved && DrumPreset.preset(id: saved.id) == nil)
    }

    @Test func emptyPatternsAndBlankNamesAreNotSaved() {
        var pattern = DrumPattern()
        pattern.addTrack(sampleID: 1, label: "Kick", category: "Kick", starter: false)
        #expect(pattern.makePreset(name: "Silent", bpm: 120) == nil, "no steps")
        pattern.toggle(track: 0, step: 0)
        #expect(pattern.makePreset(name: "   ", bpm: 120) == nil)
        #expect(pattern.makePreset(name: String(repeating: "a", count: 100), bpm: 500)?.name.count == DrumPreset.maxNameLength)
        #expect(pattern.makePreset(name: "x", bpm: 500)?.bpm == 300, "tempo is kept in range")
    }
}
