import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct JoinTests {
    @Test func silenceFitsBetweenSoundsAndStaysOutsideTheirCues() throws {
        let plans = try JoinPlanner.plan(frameCounts: [44_100, 22_050],
                                         settings: JoinSettings(maxSeconds: 2, silenceSeconds: 0.25, maxCuePoints: 64))
        #expect(plans == [JoinedFilePlan(regions: [
            JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 44_100),
            JoinedRegion(sourceIndex: 1, startFrame: 55_125, endFrame: 77_175),
        ])], "Only the space between sounds is silent, and the end cue excludes it.")
    }

    @Test func maximumLengthIncludesTheSilenceAndKeepsWholeSounds() throws {
        let plans = try JoinPlanner.plan(frameCounts: [44_100, 44_100, 44_100],
                                         settings: JoinSettings(maxSeconds: 2.25, silenceSeconds: 0.25, maxCuePoints: 64))
        #expect(plans.map(\.frameCount) == [99_225, 44_100], "A file may exactly reach the limit, but never pass it.")
        #expect(plans.map { $0.regions.map(\.sourceIndex) } == [[0, 1], [2]])
    }

    @Test func maximumCueCountStartsAnotherFile() throws {
        let plans = try JoinPlanner.plan(frameCounts: [100, 200, 300],
                                         settings: JoinSettings(maxSeconds: 11, silenceSeconds: 0, maxCuePoints: 2))
        #expect(plans.map { $0.regions.count } == [2, 1], "Each source is one selectable cue set.")
        #expect(plans.last?.regions.first?.startFrame == 0, "Every output starts with a sound, not silence.")
    }

    @Test func oversizedOrEmptySoundsAndInvalidLimitsAreRejected() {
        #expect(throws: JoinError.self) {
            try JoinPlanner.plan(frameCounts: [44_101], settings: JoinSettings(maxSeconds: 1))
        }
        for settings in [
            JoinSettings(maxSeconds: .nan), JoinSettings(maxSeconds: .infinity),
            JoinSettings(maxSeconds: 0), JoinSettings(silenceSeconds: -1),
            JoinSettings(silenceSeconds: .infinity), JoinSettings(maxCuePoints: 0),
            JoinSettings(maxSeconds: 301), JoinSettings(silenceSeconds: 301),
            JoinSettings(maxCuePoints: 65_537), JoinSettings(maxSeconds: 0.000001),
        ] {
            #expect(throws: JoinError.self) { try JoinPlanner.plan(frameCounts: [100], settings: settings) }
        }
        #expect(throws: JoinError.self) { try JoinPlanner.plan(frameCounts: [0], settings: JoinSettings()) }
    }
}
