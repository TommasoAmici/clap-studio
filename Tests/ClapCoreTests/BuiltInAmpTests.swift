import Foundation
import Testing
@testable import ClapCore

@Suite struct BuiltInAmpTests {
    @Test func dryMixKeepsBothChannelsUnchanged() {
        var parameters = BuiltInEffect.amplifier.makeSlot().parameters
        parameters[3].value = 0
        let amp = AmpProcessor(sampleRate: 44_100, parameters: parameters)
        var left: [Float] = [0, 0.2, -0.3, 0.7], right: [Float] = [-0.1, 0.4, 0.2, -0.5]
        let dryLeft = left, dryRight = right
        amp.process(left: &left, right: &right)
        #expect(left == dryLeft && right == dryRight, "Zero mix preserves the original stereo signal")
    }

    @Test func driveAddsHarmonicsWithoutNonFiniteSamples() {
        var parameters = BuiltInEffect.amplifier.makeSlot().parameters
        parameters[0].value = 1
        let amp = AmpProcessor(sampleRate: 44_100, parameters: parameters)
        var left = (0..<512).map { Float(sin(2 * .pi * Double($0) / 64) * 0.4) }, right = left
        let input = left
        amp.process(left: &left, right: &right)
        #expect(left != input && left.allSatisfy(\.isFinite) && left == right,
                "Drive colours the sound and keeps equal channels equal")
    }

    @Test @MainActor func previewUpdatesAndBypassesBuiltInEffects() throws {
        var slot = BuiltInEffect.amplifier.makeSlot()
        let processor = try VST3LiveProcessor(chain: [slot], sampleRate: 44_100)
        defer { processor.close() }
        var left = [Float](repeating: 0.3, count: 128), right = left
        try processor.process(left: &left, right: &right)
        #expect(abs(left.last! - 0.3) > 0.01, "An enabled amp changes preview audio")
        slot.bypass = true
        try processor.update([slot])
        left = [Float](repeating: 0.3, count: 128); right = left
        try processor.process(left: &left, right: &right)
        #expect(left.allSatisfy { $0 == 0.3 }, "Bypass leaves audition audio dry")
        slot.bypass = false; slot.parameters[3].value = 0
        try processor.update([slot])
        left = [Float](repeating: 0.3, count: 128); right = left
        try processor.process(left: &left, right: &right)
        #expect(left.allSatisfy { $0 == 0.3 }, "Mix changes reach the next preview block")
        #expect(try processor.snapshot().first == slot, "The chain keeps the changed controls")
    }

    @Test @MainActor func externalAndBuiltInEffectsKeepTheirOrderAndSettings() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugin = try #require(try await VST3Plugin.effects(in: VST3Fixture.bundle(in: folder)).first)
        var gain = try await plugin.makeSlot()
        gain.parameters[0].value = 0.5
        var amp = BuiltInEffect.amplifier.makeSlot()
        amp.parameters[0].value = 1
        let first = try VST3LiveProcessor(chain: [gain, amp], sampleRate: 44_100)
        let second = try VST3LiveProcessor(chain: [amp, gain], sampleRate: 44_100)
        defer { first.close(); second.close() }
        var before = [Float](repeating: 0.3, count: 128), beforeRight = before
        var after = before, afterRight = before
        try first.process(left: &before, right: &beforeRight)
        try second.process(left: &after, right: &afterRight)
        #expect(abs(before.last! - after.last!) > 0.02, "The chain honours order between a plug-in and a built-in amp")
        amp.bypass = true
        try first.update([gain, amp])
        before = [Float](repeating: 0.3, count: 128); beforeRight = before
        try first.process(left: &before, right: &beforeRight)
        #expect(abs(before.last! - 0.15) < 0.001, "Bypassing the amp leaves the plug-in in the chain")
        let saved = try first.snapshot()
        #expect(saved.last == amp, "The amp's bypass and control settings survive a live snapshot")
    }

    @Test func bounceAppliesAmpWithoutChangingTheOriginal() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav"), target = folder.appendingPathComponent("amp.wav")
        try writeTestWav(source, seconds: 0.05) { _ in 0.3 }
        let original = try Data(contentsOf: source)
        try await EffectBounce.write(source: source, trim: nil, chain: [BuiltInEffect.amplifier.makeSlot()], to: target, tailSeconds: 0)
        let samples = try AudioDecoder.decode(url: target, start: 0, seconds: 0.02, sampleRate: 44_100)
        #expect(abs((samples.max() ?? 0) - 0.3) > 0.01, "Bounces use the same built-in amp")
        #expect(try Data(contentsOf: source) == original, "Bouncing leaves the source untouched")
    }
}
