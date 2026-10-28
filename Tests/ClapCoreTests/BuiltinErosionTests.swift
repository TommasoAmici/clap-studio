import Foundation
import Testing
@testable import ClapCore

@Suite struct BuiltinErosionTests {
    private func settings(_ values: [UInt32: Double]) -> [VST3Parameter] {
        BuiltinErosion.defaults.map { parameter in
            var parameter = parameter
            if let value = values[parameter.id] { parameter.value = value }
            return parameter
        }
    }

    private func signal(_ count: Int) -> [Float] {
        (0..<count).map { Float(sin(Double($0) * 0.36) * 0.6 + sin(Double($0) * 0.113) * 0.2) }
    }

    @Test func zeroAmountKeepsStereoAudioUnchanged() {
        let processor = BuiltinErosion(sampleRate: 44_100, parameters: settings([1: 0, 2: 1, 4: 1]))
        var left = signal(1024), right = left.reversed().map { $0 }
        let inputLeft = left, inputRight = right
        processor.process(left: &left, right: &right)
        #expect(left == inputLeft && right == inputRight, "Zero amount preserves both channels without adding latency")
    }

    @Test func changingTheAmountChangesTheNextBlock() {
        let processor = BuiltinErosion(sampleRate: 44_100, parameters: settings([1: 0, 2: 0]))
        var left = signal(1024), right = left
        processor.process(left: &left, right: &right)
        processor.update(parameters: settings([0: 0.5, 1: 1, 2: 0]))
        let input = signal(1024)
        left = input; right = input
        processor.process(left: &left, right: &right)
        #expect(zip(left, input).contains { abs($0 - $1) > 0.01 }, "Increasing amount makes the delay modulation audible on the next block")
        #expect(left == right, "A mono modulation source leaves equal input channels equal")
    }

    @Test func stereoWidthSeparatesModulationWithoutAddingNoiseToSilence() {
        let processor = BuiltinErosion(sampleRate: 44_100, parameters: settings([1: 1, 2: 1, 4: 1]))
        var left = [Float](repeating: 0, count: 256), right = left
        processor.process(left: &left, right: &right)
        #expect(left.allSatisfy { $0 == 0 } && right == left, "Modulation does not add noise to silent audio")
        left = signal(4096); right = left
        processor.process(left: &left, right: &right)
        #expect(zip(left, right).contains { abs($0 - $1) > 0.001 }, "Stereo width gives identical channels independent modulation")
    }

    @Test func carrierAndNoiseFilterControlsChangeTheSound() {
        func render(_ values: [UInt32: Double]) -> [Float] {
            let processor = BuiltinErosion(sampleRate: 48_000, parameters: settings(values))
            var left = signal(4096), right = left
            processor.process(left: &left, right: &right)
            return left
        }
        let sine = render([0: 0.5, 1: 1, 2: 0, 3: 0])
        let noise = render([0: 0.5, 1: 1, 2: 1, 3: 0])
        let wide = render([0: 0.5, 1: 1, 2: 1, 3: 1])
        let high = render([0: 0.9, 1: 1, 2: 1, 3: 1])
        #expect(sine != noise, "Noise blend selects a different modulation carrier")
        #expect(noise != wide, "Filter width changes the noise carrier")
        #expect(wide != high, "Frequency changes the noise carrier")
    }

    @Test func blocksAndSampleRatesProduceStableFiniteAudio() {
        for rate in [44_100.0, 96_000.0] {
            let options = settings([0: 1, 1: 1, 2: 0.75, 3: 1, 4: 1])
            let whole = BuiltinErosion(sampleRate: rate, parameters: options)
            let pieces = BuiltinErosion(sampleRate: rate, parameters: options)
            let input = signal(4096)
            var left = input, right = input
            whole.process(left: &left, right: &right)
            var splitLeft: [Float] = [], splitRight: [Float] = []
            for start in stride(from: 0, to: input.count, by: 257) {
                var l = Array(input[start..<min(start + 257, input.count)]), r = l
                pieces.process(left: &l, right: &r)
                splitLeft += l; splitRight += r
            }
            #expect(left == splitLeft && right == splitRight, "Audio is independent of the host's block boundaries")
            #expect(left.allSatisfy(\.isFinite) && right.allSatisfy(\.isFinite), "Normal audio remains finite at both sample rates")
            #expect(whole.tailFrames > 0 && Double(whole.tailFrames) / rate < 0.01, "The reported tail covers only the short delay")
        }
    }
    @Test @MainActor func chainUpdatesErosionAndBypassKeepsAudioDry() throws {
        var slot = BuiltInEffect.erosion.makeSlot()
        let processor = try VST3LiveProcessor(chain: [slot], sampleRate: 44_100)
        defer { processor.close() }
        let input = signal(512)
        var left = input, right = input
        slot.bypass = true
        try processor.update([slot])
        try processor.process(left: &left, right: &right)
        #expect(left == input && right == input, "Bypass keeps the selected sample dry")

        slot.bypass = false
        slot.parameters[1].value = 1
        slot.parameters[2].value = 0
        try processor.update([slot])
        left = input; right = input
        try processor.process(left: &left, right: &right)
        #expect(zip(left, input).contains { abs($0 - $1) > 0.01 }, "The next preview block uses the changed amount")
        #expect(try processor.snapshot() == [slot], "The current erosion settings survive a live snapshot")
    }

    @Test @MainActor func helperBouncesErosionWithoutChangingTheOriginal() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav")
        let dry = folder.appendingPathComponent("dry.wav"), wet = folder.appendingPathComponent("erosion.wav")
        try writeTestWav(source, seconds: 0.1) { Float(sin(2 * .pi * 5_000 * $0)) * 0.5 }
        let original = try Data(contentsOf: source)
        var slot = BuiltInEffect.erosion.makeSlot()
        slot.parameters[1].value = 1; slot.parameters[2].value = 0
        try await EffectBounce.write(source: source, trim: nil, chain: [slot], to: wet, tailSeconds: 0)
        slot.bypass = true
        try await EffectBounce.write(source: source, trim: nil, chain: [slot], to: dry, tailSeconds: 0)
        let altered = try AudioDecoder.decode(url: wet, start: 0, seconds: 0.08, sampleRate: 44_100)
        let unaltered = try AudioDecoder.decode(url: dry, start: 0, seconds: 0.08, sampleRate: 44_100)
        #expect(zip(altered, unaltered).contains { abs($0 - $1) > 0.01 }, "The helper applies erosion to the independent bounce")
        #expect(try Data(contentsOf: source) == original, "The original sample remains unchanged")
    }

}
