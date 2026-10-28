import CVST3
import Foundation

/// Owns an editor and its settings exclusively inside the helper.
@MainActor public final class VST3EditorSession {
    public let editor: UnsafeMutableRawPointer
    private let instance: VST3Instance
    private let slot: EffectSlot
    private var closed = false
    private let ownsInstance: Bool

    public init(slot: EffectSlot) throws {
        let instance = try VST3Instance(slot: slot)
        guard let editor = clap_vst3_editor_create(instance.effect) else {
            instance.close()
            throw VST3Error.message("This plug-in has no native Mac editor. Use its parameter controls.")
        }
        self.instance = instance; self.editor = editor; self.slot = slot; ownsInstance = true
    }

    init(instance: VST3Instance, slot: EffectSlot) throws {
        guard let editor = clap_vst3_editor_create(instance.effect) else {
            throw VST3Error.message("This plug-in has no native Mac editor. Use its parameter controls.")
        }
        self.instance = instance; self.editor = editor; self.slot = slot; ownsInstance = false
    }

    public func snapshot() throws -> EffectSlot {
        guard !closed else { throw VST3Error.message("The plug-in editor was closed.") }
        return try instance.snapshot(slot)
    }

    public func close() {
        guard !closed else { return }
        clap_vst3_editor_destroy(editor)
        if ownsInstance { instance.close() }; closed = true
    }
}
