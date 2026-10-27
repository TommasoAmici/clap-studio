import CVST3
import Foundation

/// Owns an editor and its settings exclusively inside the helper.
@MainActor public final class VST3EditorSession {
    public let editor: UnsafeMutableRawPointer
    private let instance: VST3Instance
    private let slot: EffectSlot
    private var closed = false

    public init(slot: EffectSlot) throws {
        let instance = try VST3Instance(slot: slot)
        guard let editor = clap_vst3_editor_create(instance.effect) else {
            instance.close()
            throw VST3Error.message("This plug-in has no native Mac editor. Use its parameter controls.")
        }
        self.instance = instance; self.editor = editor; self.slot = slot
    }

    public func snapshot() throws -> EffectSlot { try instance.snapshot(slot) }

    public func close() {
        guard !closed else { return }
        clap_vst3_editor_destroy(editor)
        instance.close(); closed = true
    }
}
