import Foundation
import Testing
@testable import ClapCore

@Suite struct BuiltInReverbChainTests {
    @Test @MainActor func previewUpdatesTailAndBypassesTheRoom() throws {
        var slot = BuiltInEffect.reverb.makeSlot()
        let processor = try VST3LiveProcessor(chain: [slot], sampleRate: 44_100)
        defer { processor.close() }
        let shortTail = processor.tailFrames
        slot.parameters[2].value = 1
        slot.parameters[5].value = 1
        try processor.update([slot])
        #expect(processor.tailFrames > shortTail, "A longer decay gives the live preview time to ring out")
        #expect(try processor.snapshot().first == slot, "The preview preserves reverb settings")
        var left = [Float](repeating: 0.25, count: 512), right = left
        try processor.process(left: &left, right: &right)
        #expect(left.allSatisfy { $0 == 0 }, "A fully wet room begins with delayed reflections")
        slot.bypass = true
        try processor.update([slot])
        #expect(processor.tailFrames == 0, "A bypassed room should not add silence to the next audition")
        let bypassed = try VST3LiveProcessor(chain: [slot], sampleRate: 44_100)
        defer { bypassed.close() }
        #expect(bypassed.tailFrames == 0, "A chain created with bypass enabled also reports no room tail")
        left = [Float](repeating: 0.25, count: 512); right = left
        try processor.process(left: &left, right: &right)
        #expect(left.allSatisfy { $0 == 0.25 } && right == left, "Bypass keeps the preview dry")
    }

    @Test func changingDecayExtendsAnAlreadyPlayingPreview() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let directory = folder.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let source = folder.appendingPathComponent("sound.wav")
        try writeTestWav(source, seconds: 10) { _ in 0.1 }
        var slot = BuiltInEffect.reverb.makeSlot()
        slot.parameters[0].value = 0; slot.parameters[2].value = 0; slot.bypass = true
        var request = VST3HostRequest(operation: .live, chain: [slot])
        request.sessionDirectory = directory
        let task = Task { try await VST3HostRequest.send(request) }
        defer { task.cancel() }
        func waitFor(_ action: String, _ url: URL, matching: (VST3LiveStatus) -> Bool) async throws -> VST3LiveStatus {
            var last: VST3LiveStatus?
            for _ in 0..<500 {
                if let data = try? Data(contentsOf: url), let status = try? JSONDecoder().decode(VST3LiveStatus.self, from: data) {
                    last = status
                    if let error = status.error { throw VST3Error.message(error) }
                    if matching(status) { return status }
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw VST3Error.message("Timed out waiting for \(action). Last sample: \(last?.sampleID.map(String.init) ?? "none"); duration: \(last?.duration ?? 0).")
        }
        let statusURL = directory.appendingPathComponent("status.json")
        _ = try await waitFor("the initial chain", statusURL) { $0.chain?.first?.id == slot.id }
        var play = VST3LiveCommand(operation: .play)
        play.source = source; play.sampleID = 9; play.tailSeconds = 0
        try JSONEncoder().encode(play).write(to: directory.appendingPathComponent("command-00000001.json"), options: .atomic)
        let started = try await waitFor("the first audition", statusURL) { $0.sampleID == 9 }
        slot.parameters[2].value = 1; slot.bypass = false
        var update = VST3LiveCommand(operation: .update); update.chain = [slot]
        try JSONEncoder().encode(update).write(to: directory.appendingPathComponent("command-00000002.json"), options: .atomic)
        let id = UUID()
        var snapshot = VST3LiveCommand(operation: .snapshot); snapshot.requestID = id
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("command-00000003.json"), options: .atomic)
        let updated = try await waitFor("updated settings", directory.appendingPathComponent("reply-\(id).json")) { $0.requestID == id }
        #expect(updated.sampleID == 9 && updated.duration > started.duration + 5,
                "Enabling a longer room during playback extends the live sample and its reported duration")
        try JSONEncoder().encode(VST3LiveCommand(operation: .stop))
            .write(to: directory.appendingPathComponent("command-00000004.json"), options: .atomic)
        play.sampleID = 10
        try JSONEncoder().encode(play).write(to: directory.appendingPathComponent("command-00000005.json"), options: .atomic)
        _ = try await waitFor("the replacement audition", statusURL) { $0.sampleID == 10 }
        try await Task.sleep(for: .milliseconds(1_600))
        let nextID = UUID()
        snapshot.requestID = nextID
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("command-00000006.json"), options: .atomic)
        let next = try await waitFor("replacement settings", directory.appendingPathComponent("reply-\(nextID).json")) { $0.requestID == nextID }
        #expect(next.sampleID == 10, "Stopping and starting another audition ignores callbacks from the previous sample")
    }

    @Test func helperBounceKeepsAudibleTailAndSource() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav"), first = folder.appendingPathComponent("room.wav")
        let second = folder.appendingPathComponent("room-again.wav")
        try writeTestWav(source, seconds: 0.05) { Float(sin(2 * .pi * 440 * $0)) * 0.25 }
        let original = try Data(contentsOf: source)
        var slot = BuiltInEffect.reverb.makeSlot()
        slot.parameters[0].value = 0
        slot.parameters[2].value = 0.5
        slot.parameters[5].value = 1
        try await EffectBounce.write(source: source, trim: nil, chain: [slot], to: first, tailSeconds: 0)
        let info = try AudioDecoder.fileInfo(url: first)
        #expect(info.duration > 0.2, "The reported reverb tail extends a bounce even without extra padding")
        let tail = try AudioDecoder.decode(url: first, start: 0.1, seconds: 0.05, sampleRate: 44_100)
        #expect(tail.contains { abs($0) > 0.000_01 }, "The rendered tail contains audible room reflections")
        #expect(try Data(contentsOf: source) == original, "The helper never changes the original sample")
        try await EffectBounce.write(source: source, trim: nil, chain: [slot], to: second, tailSeconds: 0)
        #expect(try Data(contentsOf: first) == Data(contentsOf: second), "Each bounce starts with an empty room")
    }
}
