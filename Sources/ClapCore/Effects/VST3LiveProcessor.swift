import CVST3
import Foundation

/// A short-block effects chain owned by the helper, shared with its editors.
@MainActor public final class VST3LiveProcessor {
    private var closed = false
    private var recipe: [EffectSlot]
    private var editors: [VST3EditorSession] = []
    private var instances: [UUID: VST3Instance] = [:]
    public let sampleRate: Double
    public private(set) var tailFrames = 0

    public init(chain: [EffectSlot], sampleRate: Double) throws {
        self.recipe = chain; self.sampleRate = sampleRate
        do {
            for slot in chain {
                let instance = try VST3Instance(slot: slot)
                instances[slot.id] = instance
                try instance.prepare(rate: sampleRate, live: true)
                let latency = clap_vst3_latency(instance.effect)
                guard Double(latency) <= sampleRate * 30 else {
                    throw VST3Error.message("This effect reports more than 30 seconds of latency.")
                }
                tailFrames += min(Int(clap_vst3_tail(instance.effect)), Int(sampleRate * EffectBounce.maximumTailSeconds))
            }
        } catch { close(); throw error }
    }

    /// Reuses the processors for parameter and bypass changes, preserving ringing tails.
    public func update(_ chain: [EffectSlot]) throws {
        guard !closed, chain.map(\.id) == recipe.map(\.id), zip(chain, recipe).allSatisfy({ $0.plugin == $1.plugin }) else {
            throw VST3Error.message("The effects chain changed. Start a new preview session.")
        }
        for slot in chain {
            guard let instance = instances[slot.id] else { continue }
            for parameter in slot.parameters {
                let value = parameter.value.isFinite ? min(1, max(0, parameter.value)) : 0
                _ = clap_vst3_parameter_set(instance.effect, parameter.id, value)
            }
        }
        recipe = chain
    }

    /// Processes at most 512 frames at a time; playback never waits for the rest of the file.
    public func process(left: inout [Float], right: inout [Float]) throws {
        guard !closed, !left.isEmpty, left.count == right.count, left.count <= 512 else {
            throw VST3Error.message("Invalid preview audio block.")
        }
        for slot in recipe where !slot.bypass {
            guard let instance = instances[slot.id] else { continue }
            let parameters = instance.parameterValues()
            let ids = parameters.map(\.id), values = parameters.map(\.value)
            guard clap_vst3_process(instance.effect, &left, &right, Int32(left.count), ids, values, Int32(ids.count)) != 0 else {
                throw VST3Error.message("The effect could not play this sample. Original files are unchanged.")
            }
            guard left.allSatisfy(\.isFinite), right.allSatisfy(\.isFinite) else {
                throw VST3Error.message("The effect produced invalid audio and was stopped.")
            }
        }
    }

    public func editor(for id: UUID) throws -> VST3EditorSession {
        guard !closed, let instance = instances[id], let slot = recipe.first(where: { $0.id == id }) else {
            throw VST3Error.message("The effect is no longer in the chain.")
        }
        let editor = try VST3EditorSession(instance: instance, slot: slot)
        editors.append(editor)
        return editor
    }

    /// Poll small controller values without repeatedly serializing large presets.
    public func parameterValues() -> [[VST3Parameter]] {
        recipe.map { instances[$0.id]?.parameterValues() ?? [] }
    }

    public func snapshot() throws -> [EffectSlot] {
        guard !closed else { throw VST3Error.message("The effects session was closed.") }
        return try recipe.map { slot in
            guard let instance = instances[slot.id] else { return slot }
            return try instance.snapshot(slot)
        }
    }

    public func close() {
        guard !closed else { return }; closed = true
        for editor in editors { editor.close() }; editors.removeAll()
        for instance in instances.values { instance.close() }
        instances.removeAll()
    }
}
