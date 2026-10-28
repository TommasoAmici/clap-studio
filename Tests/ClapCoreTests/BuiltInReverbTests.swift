import Foundation
import Testing
@testable import ClapCore

@Suite struct BuiltInReverbTests {
    private func parameters(_ changes: [(Int, Double)] = []) -> [VST3Parameter] {
        var parameters = BuiltInReverb.defaultParameters
        for (index, value) in changes { parameters[index].value = value }
        return parameters
    }

    private func render(_ reverb: BuiltInReverb, samples: Int, blockSize: Int) -> ([Float], [Float]) {
        var allLeft: [Float] = [], allRight: [Float] = []
        for start in stride(from: 0, to: samples, by: blockSize) {
            let count = min(blockSize, samples - start)
            var left = [Float](repeating: 0, count: count), right = left
            if start == 0 { left[0] = 1; right[0] = 1 }
            reverb.process(left: &left, right: &right)
            allLeft += left; allRight += right
        }
        return (allLeft, allRight)
    }

    @Test func dryMixPreservesStereoInput() {
        let reverb = BuiltInReverb(sampleRate: 44_100, parameters: parameters([(5, 0)]))
        var left: [Float] = [0, 0.3, -0.8, 1], right: [Float] = [0.4, -0.3, 0.1, -0.2]
        let dryLeft = left, dryRight = right
        reverb.process(left: &left, right: &right)
        #expect(left == dryLeft && right == dryRight, "A dry mix must preserve both channels exactly")
    }

    @Test func impulseRingsAndDecaysIndependentlyAcrossStereo() {
        let reverb = BuiltInReverb(sampleRate: 44_100, parameters: parameters([(0, 0), (2, 0.2), (5, 1)]))
        let (left, right) = render(reverb, samples: 132_300, blockSize: 512)
        let first = left[0..<22_050].reduce(0.0) { $0 + Double($1 * $1) }
        let late = left[88_200..<110_250].reduce(0.0) { $0 + Double($1 * $1) }
        #expect(first > 0.0001 && late < first * 0.01, "A short decay produces audible reflections that die away")
        #expect(left != right && left.allSatisfy(\.isFinite) && right.allSatisfy(\.isFinite),
                "A wide reverb stays finite and gives each channel a different reflection pattern")
    }

    @Test func processingDoesNotDependOnBlockSize() {
        let settings = parameters([(0, 0.2), (2, 0.55), (5, 1)])
        let large = render(BuiltInReverb(sampleRate: 44_100, parameters: settings), samples: 17_000, blockSize: 512)
        let small = render(BuiltInReverb(sampleRate: 44_100, parameters: settings), samples: 17_000, blockSize: 37)
        #expect(large.0 == small.0 && large.1 == small.1, "Preview blocks must not reset the room's reflections")
    }

    @Test func longerDecayProducesLongerTailAtDifferentSampleRates() {
        for sampleRate in [22_050.0, 48_000.0] {
            let short = BuiltInReverb(sampleRate: sampleRate, parameters: parameters([(0, 0), (2, 0), (5, 1)]))
            let long = BuiltInReverb(sampleRate: sampleRate, parameters: parameters([(0, 0), (2, 1), (5, 1)]))
            let s = render(short, samples: Int(sampleRate * 2), blockSize: 512).0
            let l = render(long, samples: Int(sampleRate * 2), blockSize: 512).0
            let start = Int(sampleRate * 1.5)
            let shortEnergy = s[start...].reduce(0.0) { $0 + Double($1 * $1) }
            let longEnergy = l[start...].reduce(0.0) { $0 + Double($1 * $1) }
            #expect(longEnergy > shortEnergy * 10, "A longer decay must keep ringing at each source sample rate")
            #expect(long.tailFrames > short.tailFrames && long.tailFrames <= Int(sampleRate * 10),
                    "The reported tail follows decay without exceeding the chain's ten-second limit")
        }
    }

    @Test func predelayAndStereoWidthShapeTheReflections() {
        let immediate = BuiltInReverb(sampleRate: 44_100, parameters: parameters([(0, 0), (4, 1), (5, 1)]))
        let delayed = BuiltInReverb(sampleRate: 44_100, parameters: parameters([(0, 0.5), (4, 0), (5, 1)]))
        let wide = render(immediate, samples: 12_000, blockSize: 512)
        let mono = render(delayed, samples: 12_000, blockSize: 512)
        let firstWide = wide.0.firstIndex { abs($0) > 0.000_001 } ?? 12_000
        let firstMono = mono.0.firstIndex { abs($0) > 0.000_001 } ?? 12_000
        #expect(firstMono - firstWide >= 2_200, "Predelay holds back the wet signal by the requested time")
        #expect(mono.0 == mono.1, "Zero width sends the same reverb to both channels")
    }

    @Test func sizeAndDampingChangeTheRoomSound() {
        let bright = BuiltInReverb(sampleRate: 44_100, parameters: parameters([(0, 0), (1, 0.5), (2, 0.8), (3, 0), (5, 1)]))
        let damped = BuiltInReverb(sampleRate: 44_100, parameters: parameters([(0, 0), (1, 0.5), (2, 0.8), (3, 1), (5, 1)]))
        let small = BuiltInReverb(sampleRate: 44_100, parameters: parameters([(0, 0), (1, 0), (2, 0.8), (3, 0), (5, 1)]))
        let brightLeft = render(bright, samples: 44_100, blockSize: 512).0
        let dampedLeft = render(damped, samples: 44_100, blockSize: 512).0
        let smallLeft = render(small, samples: 44_100, blockSize: 512).0
        let brightEnergy = brightLeft.suffix(22_050).reduce(0.0) { $0 + Double($1 * $1) }
        let dampedEnergy = dampedLeft.suffix(22_050).reduce(0.0) { $0 + Double($1 * $1) }
        #expect(dampedEnergy < brightEnergy, "Damping absorbs energy from the repeated reflections")
        #expect(smallLeft != brightLeft, "Changing room size changes the reflection pattern")
    }

    @Test func invalidAndLiveSettingsRemainFiniteAndUpdateTail() {
        var settings = parameters([(0, .nan), (1, -.infinity), (2, .infinity), (3, 9), (4, -4), (5, 1)])
        let reverb = BuiltInReverb(sampleRate: 44_100, parameters: settings)
        let initialTail = reverb.tailFrames
        settings[2].value = 1
        reverb.update(parameters: settings)
        #expect(reverb.tailFrames > initialTail, "Changing decay updates the tail used by preview and bounce")
        let (left, right) = render(reverb, samples: 44_100, blockSize: 512)
        #expect(left.allSatisfy(\.isFinite) && right.allSatisfy(\.isFinite), "Invalid controls cannot poison the reverb state")
    }
}
