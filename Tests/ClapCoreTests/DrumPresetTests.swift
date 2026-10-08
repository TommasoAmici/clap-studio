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
}
