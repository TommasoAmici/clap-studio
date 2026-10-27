import Foundation
import Testing
@testable import ClapCore

@Suite(.serialized) struct VST3EditorTests {
    @Test func editorReturnsTheWholeRecipeIncludingHiddenState() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try VST3Fixture.bundle(in: folder)
        let plugin = try #require(try await VST3Plugin.effects(in: bundle).first)
        let slot = try await plugin.makeSlot()
        #expect(slot.hasEditor, "The fixture supplies an NSView editor")
        var request = VST3HostRequest(operation: .editor, slot: slot)
        request.editorCloseAfter = 0.2
        let edited = try #require(try await VST3HostRequest.send(request).slot)
        #expect(edited.id == slot.id, "Editing replaces the recipe while keeping the effect’s place in the chain")
        #expect(edited.parameters.first?.value == 0.25, "The manufacturer editor changed its exposed gain")
        #expect(edited.componentState != nil && edited.controllerState != nil, "Presets and internal settings accompany normalized parameters")
        let source = folder.appendingPathComponent("source.wav"), target = folder.appendingPathComponent("editor.wav")
        try writeTestWav(source, seconds: 0.05) { _ in 0.25 }
        try await EffectBounce.write(source: source, trim: nil, chain: [edited], to: target, tailSeconds: 0)
        let rendered = try AudioDecoder.decode(url: target, start: 0, seconds: 0.02, sampleRate: 44100)
        #expect(abs((rendered.max() ?? 0) - 0.1875) < 0.001, "A fresh helper restores the hidden 0.125 offset as well as the 0.25 gain")
        var reopened = VST3HostRequest(operation: .editor, slot: edited)
        reopened.editorCloseAfter = 0.2
        let again = try #require(try await VST3HostRequest.send(reopened).slot)
        #expect(again.componentState == edited.componentState, "Reopening starts with the saved manufacturer settings")
    }

    @Test func aResponsiveEditorOutlivesItsStartupDeadline() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try VST3Fixture.bundle(in: folder)
        let plugin = try #require(try await VST3Plugin.effects(in: bundle).first)
        let slot = try await plugin.makeSlot()
        var request = VST3HostRequest(operation: .editor, slot: slot)
        request.editorCloseAfter = 1.5
        let reply = try await VST3HostRequest.send(request, timeout: 1)
        #expect(reply.slot?.id == slot.id, "A responsive editor remains open until the user closes it")
    }

    @Test func pluginsWithoutNativeViewsKeepGenericControls() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try VST3Fixture.bundle(in: folder, withEditor: false)
        let plugin = try #require(try await VST3Plugin.effects(in: bundle).first)
        let slot = try await plugin.makeSlot()
        #expect(!slot.hasEditor && !slot.parameters.isEmpty, "An effect without an NSView editor remains editable through its parameters")
    }
}
