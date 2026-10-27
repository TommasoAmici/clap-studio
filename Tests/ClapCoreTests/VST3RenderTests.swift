import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct VST3RenderTests {
    @Test func emptyChainKeepsTrimAndWritesAnIndependentCopy() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav")
        try writeTestWav(source, seconds: 0.2) { Float(sin(2 * .pi * 440 * $0)) * 0.25 }
        let original = try Data(contentsOf: source)
        let destination = folder.appendingPathComponent("bounce.wav")
        try await EffectBounce.write(source: source, trim: SampleTrim(start: 0.05, end: 0.15), chain: [], to: destination)
        #expect(try Data(contentsOf: source) == original, "Bouncing never changes the source")
        let info = try AudioDecoder.fileInfo(url: destination)
        #expect(abs(info.duration - 0.1) < 0.002, "The bounce starts from the library trim")
        #expect(info.channels == 2, "Effects bounces use stereo WAV")
    }
    @Test func refusingSourceDestinationKeepsOriginalBytes() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav")
        try writeTestWav(source, seconds: 0.1) { Float(sin(2 * .pi * 440 * $0)) * 0.25 }
        let original = try Data(contentsOf: source)
        await #expect(throws: (any Error).self) { try await EffectBounce.write(source: source, trim: nil, chain: [], to: source) }
        #expect(try Data(contentsOf: source) == original)
    }
    @Test func otherOriginalsAndTheirHardLinksCannotBeReplaced() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.wav"), second = folder.appendingPathComponent("second.wav")
        try writeTestWav(first, seconds: 0.1) { _ in 0.25 }
        try writeTestWav(second, seconds: 0.1) { _ in 0.5 }
        let link = folder.appendingPathComponent("linked.wav")
        try FileManager.default.linkItem(at: second, to: link)
        let original = try Data(contentsOf: second)
        for destination in [second, link] {
            await #expect(throws: (any Error).self) {
                try await EffectBounce.write(source: first, trim: nil, chain: [], to: destination, protectedSources: [second])
            }
        }
        #expect(try Data(contentsOf: second) == original, "A bounce cannot overwrite another selected sample or its hard link")
    }
    @Test func cancellationKeepsAnExistingDestination() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav"), target = folder.appendingPathComponent("target.wav")
        try writeTestWav(source, seconds: 0.1) { _ in 0.25 }
        let original = Data("keep this".utf8)
        try original.write(to: target)
        let task = Task { try await EffectBounce.write(source: source, trim: nil, chain: [], to: target) }
        task.cancel()
        do { try await task.value; Issue.record("A cancelled bounce must throw") } catch { }
        #expect(try Data(contentsOf: target) == original, "Cancelling does not replace an existing file")
    }
    @Test func officialDelayCanBeLoadedAndRenderedWhenFixtureIsAvailable() async throws {
        guard let path = ProcessInfo.processInfo.environment["CLAP_VST3_TEST_PLUGIN"] else { return }
        let plugins = try await VST3Plugin.effects(in: URL(fileURLWithPath: path))
        #expect(!plugins.isEmpty, "The official VST3 fixture exposes an audio effect")
        let plugin = try #require(plugins.first)
        var params = try await plugin.parameters()
        if let delay = params.firstIndex(where: { $0.name == "Delay" }) { params[delay].value = 0.05 }
        #expect(!params.isEmpty, "Controller parameters are available for the shared chain")
        let chain = [EffectSlot(plugin: plugin, parameters: params)]
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav"), target = folder.appendingPathComponent("delay.wav")
        try writeTestWav(source, seconds: 0.1) { Float(sin(2 * .pi * 440 * $0)) * 0.25 }
        try await EffectBounce.write(source: source, trim: nil, chain: chain, to: target)
        let rendered = try AudioDecoder.decode(url: target, start: 0, seconds: 0.1, sampleRate: 44100)
        let before = rendered.prefix(1800).map { abs($0) }.max() ?? 0
        let after = rendered.dropFirst(2500).map { abs($0) }.max() ?? 0
        #expect(before < 0.001 && after > 0.1, "ADelay shifts the audio by the configured 50 ms")
        let second = folder.appendingPathComponent("delay-again.wav")
        try await EffectBounce.write(source: source, trim: nil, chain: chain, to: second)
        #expect(try Data(contentsOf: second) == Data(contentsOf: target), "Every sample gets a fresh effect instance with identical settings")
        var bypass = chain[0]; bypass.bypass = true
        let dry = folder.appendingPathComponent("dry.wav")
        try await EffectBounce.write(source: source, trim: nil, chain: [bypass], to: dry)
        let unprocessed = try AudioDecoder.decode(url: dry, start: 0, seconds: 0.01, sampleRate: 44100)
        #expect((unprocessed.map { abs($0) }.max() ?? 0) > 0.1, "Bypass leaves the beginning of the sample audible")
    }
}
