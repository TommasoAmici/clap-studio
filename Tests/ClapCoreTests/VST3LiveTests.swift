import Foundation
import Testing
@testable import ClapCore

@Suite(.serialized) struct VST3LiveTests {
    @Test @MainActor func shortBlocksReuseTheProcessorAndHearParameterChanges() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugin = try #require(try await VST3Plugin.effects(in: VST3Fixture.bundle(in: folder, realTimeOnly: true)).first)
        var slot = try await plugin.makeSlot()
        slot.parameters[0].value = 0.5
        let processor = try VST3LiveProcessor(chain: [slot], sampleRate: 44_100)
        defer { processor.close() }
        var left = [Float](repeating: 0.25, count: 512), right = left
        try processor.process(left: &left, right: &right)
        #expect(left.allSatisfy { abs($0 - 0.125) < 0.001 }, "The first short block is ready before the rest of a sample")
        slot.parameters[0].value = 0.25
        try processor.update([slot])
        left = [Float](repeating: 0.25, count: 512); right = left
        try processor.process(left: &left, right: &right)
        #expect(right.allSatisfy { abs($0 - 0.0625) < 0.001 }, "Live parameter changes reach the next block without reloading the plug-in")
        slot.bypass = true
        try processor.update([slot])
        left = [Float](repeating: 0.25, count: 512); right = left
        try processor.process(left: &left, right: &right)
        #expect(left == right && left[0] == 0.25, "Bypassing leaves dry audio unchanged")
    }

    @Test @MainActor func anEditorSharesItsProcessorAndClosingItKeepsPlaybackAvailable() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugin = try #require(try await VST3Plugin.effects(in: VST3Fixture.bundle(in: folder)).first)
        let slot = try await plugin.makeSlot()
        let processor = try VST3LiveProcessor(chain: [slot], sampleRate: 44_100)
        defer { processor.close() }
        let editor = try processor.editor(for: slot.id)
        #expect(try editor.snapshot().id == slot.id, "The editor borrows the live effect instead of a second instance")
        editor.close()
        var left = [Float](repeating: 0.25, count: 128), right = left
        try processor.process(left: &left, right: &right)
        #expect(left[0] == 0.25, "Closing a borrowed editor keeps the processor alive")
        #expect(try processor.snapshot().first?.id == slot.id)
    }
    @Test @MainActor func removingAProcessorClosesItsBorrowedEditorBeforeReleasingThePlugin() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugin = try #require(try await VST3Plugin.effects(in: VST3Fixture.bundle(in: folder)).first)
        let slot = try await plugin.makeSlot()
        let processor = try VST3LiveProcessor(chain: [slot], sampleRate: 44_100)
        let editor = try processor.editor(for: slot.id)
        processor.close()
        editor.close()
        #expect(throws: (any Error).self) { try editor.snapshot() }
        var left = [Float](repeating: 0, count: 32), right = left
        #expect(throws: (any Error).self) { try processor.process(left: &left, right: &right) }
    }
    @Test func aWarmHelperPlaysBeforeTheFileEndsAndHearsItsOpenEditor() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugin = try #require(try await VST3Plugin.effects(in: VST3Fixture.bundle(in: folder)).first)
        let slot = try await plugin.makeSlot()
        let directory = folder.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let source = folder.appendingPathComponent("long.wav")
        try writeTestWav(source, seconds: 10) { _ in 0.25 }
        let original = try Data(contentsOf: source)
        let block = folder.appendingPathComponent("first-block.json")
        var request = VST3HostRequest(operation: .live, chain: [slot])
        request.sessionDirectory = directory; request.editorCloseAfter = 2; request.liveSnapshot = block
        let task = Task { try await VST3HostRequest.send(request) }
        defer { task.cancel() }
        let statusURL = directory.appendingPathComponent("status.json")
        func waitFor(_ action: String, _ predicate: (VST3LiveStatus) -> Bool) async throws -> VST3LiveStatus {
            var last: VST3LiveStatus?
            for _ in 0..<500 {
                if let data = try? Data(contentsOf: statusURL),
                   let status = try? JSONDecoder().decode(VST3LiveStatus.self, from: data) {
                    last = status
                    if let error = status.error { throw VST3Error.message("While waiting for \(action): \(error)") }
                    if predicate(status) { return status }
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let sample = last?.sampleID.map { String($0) } ?? "none"
            let gain = (last?.chain?.first?.parameters.first?.value).map { String($0) } ?? "none"
            throw VST3Error.message("The live test helper timed out waiting for \(action). Last sample: \(sample); gain: \(gain); chain: \(last?.chain?.count ?? 0).")
        }
        _ = try await waitFor("initial chain") { $0.chain?.first?.id == slot.id }
        var edit = VST3LiveCommand(operation: .edit); edit.effectID = slot.id
        try JSONEncoder().encode(edit).write(to: directory.appendingPathComponent("command-00000001.json"), options: .atomic)
        _ = try await waitFor("editor gain") { $0.chain?.first?.parameters.first?.value == 0.25 }
        var play = VST3LiveCommand(operation: .play); play.source = source; play.sampleID = 7; play.tailSeconds = 0
        let started = ContinuousClock.now
        try JSONEncoder().encode(play).write(to: directory.appendingPathComponent("command-00000002.json"), options: .atomic)
        _ = try await waitFor("playback start") { $0.sampleID == 7 && $0.chain == nil }
        #expect(started.duration(to: .now) < .seconds(3), "A ten-second sample starts before the whole file is rendered")
        let samples = try JSONDecoder().decode([[Float]].self, from: Data(contentsOf: block))
        #expect(abs(samples[0][0] - 0.1875) < 0.001,
                "The live processor hears the editor's 0.25 gain and hidden 0.125 setting while its window remains open")
        try JSONEncoder().encode(VST3LiveCommand(operation: .stop))
            .write(to: directory.appendingPathComponent("command-00000003.json"), options: .atomic)
        _ = try await waitFor("playback stop") { $0.sampleID == nil && $0.chain == nil && $0.error == nil }
        task.cancel()
        do { _ = try await task.value; Issue.record("Closing a live session must cancel its helper") } catch is CancellationError {} catch { throw error }
        #expect(try Data(contentsOf: source) == original, "Previewing and cancelling never changes the source")
    }
    @Test @MainActor func twoSlotsOfTheSameBundleKeepIndependentStateAndCloseSafely() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugin = try #require(try await VST3Plugin.effects(in: VST3Fixture.bundle(in: folder, withEditor: false)).first)
        var first = try await plugin.makeSlot()
        first.parameters[0].value = 0.5
        var second = first; second.id = UUID()
        let processor = try VST3LiveProcessor(chain: [first, second], sampleRate: 44_100)
        var left = [Float](repeating: 0.25, count: 32), right = left
        try processor.process(left: &left, right: &right)
        #expect(abs(left[0] - 0.0625) < 0.001, "Two instances of one effect retain independent gain and run left to right")
        processor.close()
        let reopened = try VST3LiveProcessor(chain: [first], sampleRate: 44_100)
        defer { reopened.close() }
        left = [Float](repeating: 0.25, count: 32); right = left
        try reopened.process(left: &left, right: &right)
        #expect(abs(left[0] - 0.125) < 0.001, "Closing duplicate effects does not unload code still used by another instance")
    }
    @Test @MainActor func requestingFreshSettingsUsesTheWarmHelperAndClosingCancelsPendingReplies() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugin = try #require(try await VST3Plugin.effects(in: VST3Fixture.bundle(in: folder)).first)
        let slot = try await plugin.makeSlot()
        let client = VST3LiveClient()
        defer { client.close() }
        try client.start(chain: [slot])
        let fresh = try await client.snapshot()
        #expect(fresh.first?.id == slot.id && fresh.first?.componentState == slot.componentState,
                "Bounce can request complete current settings without restarting its live processor")
        try client.start(chain: [slot])
        let pending = Task { try await client.snapshot() }
        await Task.yield()
        client.close()
        do {
            _ = try await pending.value
            Issue.record("Closing a session must cancel its pending settings request")
        } catch is CancellationError {} catch { throw error }
    }

    @Test func unpublishedCommandsWaitForTheirAtomicRename() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugin = try #require(try await VST3Plugin.effects(in: VST3Fixture.bundle(in: folder)).first)
        let slot = try await plugin.makeSlot()
        let directory = folder.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let firstID = UUID(), pendingID = UUID()
        var first = VST3LiveCommand(operation: .snapshot); first.requestID = firstID
        try JSONEncoder().encode(first).write(to: directory.appendingPathComponent("command-00000001.json"))
        var pending = VST3LiveCommand(operation: .snapshot); pending.requestID = pendingID
        let temporary = directory.appendingPathComponent("command-00000002.json.sb-fixture")
        try JSONEncoder().encode(pending).write(to: temporary)
        var request = VST3HostRequest(operation: .live, chain: [slot]); request.sessionDirectory = directory
        let task = Task { try await VST3HostRequest.send(request) }
        defer { task.cancel() }
        func waitForReply(_ id: UUID) async throws {
            let reply = directory.appendingPathComponent("reply-\(id).json")
            for _ in 0..<500 {
                if FileManager.default.fileExists(atPath: reply.path) { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw VST3Error.message("The published settings command did not complete.")
        }
        try await waitForReply(firstID)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("reply-\(pendingID).json").path),
                "A Foundation atomic-write auxiliary file must not run a command before publication")
        try #require(FileManager.default.fileExists(atPath: temporary.path),
                     "The host must leave auxiliary files intact so their writer can rename them")
        try FileManager.default.moveItem(at: temporary, to: directory.appendingPathComponent("command-00000002.json"))
        try await waitForReply(pendingID)
    }
    @Test func atomicAuxiliaryNamesCannotPublishCommandsOrReplies() {
        let id = UUID().uuidString
        #expect(VST3LiveFiles.isCommand("command-00000002.json"))
        #expect(VST3LiveFiles.isCommand("command-100000000.json"), "Sequence numbers may grow beyond their minimum width")
        #expect(VST3LiveFiles.isReply("reply-\(id).json"))
        #expect(!VST3LiveFiles.isCommand("command-00000002.json.sb-c633c8cc-vS8dVo"),
                "Foundation exposes the auxiliary file before its final atomic rename")
        #expect(!VST3LiveFiles.isReply("reply-\(id).json.sb-c633c8cc-vS8dVo"),
                "Reading or deleting an auxiliary reply races the writer's rename")
        #expect(!VST3LiveFiles.isCommand("command-invalid.json"))
        #expect(!VST3LiveFiles.isReply("reply-invalid.json"))
    }

}
