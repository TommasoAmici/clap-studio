import CVST3
import Foundation

public struct VST3Parameter: Identifiable, Sendable, Equatable, Codable {
    public let id: UInt32
    public let name: String
    public var value: Double
    public let steps: Int
}

/// One audio effect class in an installed VST3 bundle.
public struct VST3Plugin: Identifiable, Sendable, Equatable, Codable {
    public let bundle: URL
    public let classID: String
    public let name: String
    public var id: String { bundle.path + ":" + classID }

    public static func effects(in bundle: URL) async throws -> [VST3Plugin] {
        try await VST3HostRequest.send(VST3HostRequest(operation: .inspect, bundle: bundle)).plugins ?? []
    }

    @MainActor static func effectsInProcess(in bundle: URL) throws -> [VST3Plugin] {
        guard let module = clap_vst3_module_open(bundle.path) else { throw VST3Error.message("Could not load \(bundle.lastPathComponent). Check that the plugin supports this Mac.") }
        defer { clap_vst3_module_close(module) }
        var effects: [VST3Plugin] = []
        for index in 0..<min(1024, clap_vst3_class_count(module)) {
            var id = [CChar](repeating: 0, count: 33), name = [CChar](repeating: 0, count: 64)
            if clap_vst3_class_info(module, index, &id, &name) != 0 {
                effects.append(VST3Plugin(bundle: bundle, classID: String(cString: id), name: String(cString: name)))
            }
        }
        return effects
    }

    public func parameters() async throws -> [VST3Parameter] {
        try await makeSlot().parameters
    }

    public func makeSlot() async throws -> EffectSlot {
        guard let slot = try await VST3HostRequest.send(VST3HostRequest(operation: .parameters, plugin: self)).slot else {
            throw VST3Error.message("The plug-in did not return its settings.")
        }
        return slot
    }

    @MainActor func slotInProcess() throws -> EffectSlot {
        let instance = try VST3Instance(plugin: self)
        defer { instance.close() }
        let editor = clap_vst3_editor_create(instance.effect)
        let hasEditor = editor != nil
        if let editor { clap_vst3_editor_destroy(editor) }
        var slot = EffectSlot(plugin: self, parameters: [])
        slot.hasEditor = hasEditor
        return try instance.snapshot(slot)
    }

}

/// A reusable recipe for bouncing copies; it does not change library samples.
public struct EffectSlot: Identifiable, Sendable, Equatable, Codable {
    public var id = UUID()
    public var plugin: VST3Plugin
    public var parameters: [VST3Parameter]
    public var bypass = false
    public var hasEditor = false
    public var componentState: Data?
    public var controllerState: Data?
    public init(plugin: VST3Plugin, parameters: [VST3Parameter]) { self.plugin = plugin; self.parameters = parameters }

    public func edited() async throws -> EffectSlot {
        guard let slot = try await VST3HostRequest.send(VST3HostRequest(operation: .editor, slot: self)).slot,
              slot.id == id, slot.plugin == plugin else { throw VST3Error.message("The plug-in did not return its settings. Your previous settings were kept.") }
        return slot
    }
}

public enum VST3Error: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

/// Owned by the main actor; only exclusive processing calls run off that actor.
final class VST3Instance: @unchecked Sendable {
    let module: UnsafeMutableRawPointer
    let effect: UnsafeMutableRawPointer
    private var closed = false

    @MainActor init(plugin: VST3Plugin) throws {
        guard let module = clap_vst3_module_open(plugin.bundle.path) else { throw VST3Error.message("Could not load \(plugin.name).") }
        guard let effect = clap_vst3_effect_create(module, plugin.classID) else {
            clap_vst3_module_close(module)
            throw VST3Error.message("Could not start \(plugin.name).")
        }
        self.module = module; self.effect = effect
    }

    @MainActor convenience init(slot: EffectSlot) throws {
        try self.init(plugin: slot.plugin)
        do {
            try restore(slot.componentState, controller: false)
            try restore(slot.controllerState, controller: true)
            for parameter in slot.parameters {
                _ = clap_vst3_parameter_set(effect, parameter.id, min(1, max(0, parameter.value.isFinite ? parameter.value : 0)))
            }
        } catch { close(); throw error }
    }

    @MainActor private func restore(_ data: Data?, controller: Bool) throws {
        guard let data else { return }
        guard data.count <= 16 * 1024 * 1024, data.withUnsafeBytes({ bytes in
            clap_vst3_state_set(effect, controller ? 1 : 0, bytes.bindMemory(to: UInt8.self).baseAddress, Int32(bytes.count))
        }) != 0 else { throw VST3Error.message("The plug-in could not restore its saved settings.") }
    }

    @MainActor func snapshot(_ recipe: EffectSlot) throws -> EffectSlot {
        var slot = recipe
        slot.parameters = []
        for index in 0..<max(0, min(4096, clap_vst3_parameter_count(effect))) {
            var id: UInt32 = 0, title = [UInt16](repeating: 0, count: 128), value = 0.0, steps: Int32 = 0
            if clap_vst3_parameter_info(effect, index, &id, &title, &value, &steps) != 0 {
                slot.parameters.append(VST3Parameter(id: id, name: String(decoding: title.prefix(while: { $0 != 0 }), as: UTF16.self),
                                                      value: value.isFinite ? min(1, max(0, value)) : 0, steps: max(0, Int(steps))))
            }
        }
        slot.componentState = try state(controller: false)
        slot.controllerState = try state(controller: true)
        return slot
    }

    @MainActor private func state(controller: Bool) throws -> Data? {
        var bytes: UnsafeMutablePointer<UInt8>?, size: Int32 = 0
        let result = clap_vst3_state_get(effect, controller ? 1 : 0, &bytes, &size)
        defer { clap_vst3_bytes_free(bytes) }
        guard result >= 0 else { throw VST3Error.message("The plug-in’s settings are too large to save safely.") }
        guard result != 0 else { return nil }
        guard let bytes else { return Data() }
        return Data(bytes: bytes, count: Int(size))
    }

    @MainActor func prepare(rate: Double) throws {
        guard clap_vst3_prepare(effect, rate) != 0 else { throw VST3Error.message("This effect does not support offline stereo audio at this sample rate.") }
    }

    @MainActor func close() {
        guard !closed else { return }
        clap_vst3_effect_destroy(effect); clap_vst3_module_close(module); closed = true
    }
}
