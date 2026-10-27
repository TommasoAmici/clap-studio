import CVST3
import Foundation

public struct VST3Parameter: Identifiable, Sendable, Equatable {
    public let id: UInt32
    public let name: String
    public var value: Double
    public let steps: Int
}

/// One audio effect class in an installed VST3 bundle.
public struct VST3Plugin: Identifiable, Sendable, Equatable {
    public let bundle: URL
    public let classID: String
    public let name: String
    public var id: String { bundle.path + ":" + classID }

    @MainActor public static func effects(in bundle: URL) throws -> [VST3Plugin] {
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

    @MainActor public func parameters() throws -> [VST3Parameter] {
        let instance = try VST3Instance(plugin: self)
        defer { instance.close() }
        var parameters: [VST3Parameter] = []
        for index in 0..<min(4096, clap_vst3_parameter_count(instance.effect)) {
            var id: UInt32 = 0, title = [UInt16](repeating: 0, count: 128), value = 0.0, steps: Int32 = 0
            if clap_vst3_parameter_info(instance.effect, index, &id, &title, &value, &steps) != 0 {
                parameters.append(VST3Parameter(id: id, name: String(decoding: title.prefix(while: { $0 != 0 }), as: UTF16.self),
                                                value: min(1, max(0, value)), steps: Int(steps)))
            }
        }
        return parameters
    }
}

/// A reusable recipe for bouncing copies; it does not change library samples.
public struct EffectSlot: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public var plugin: VST3Plugin
    public var parameters: [VST3Parameter]
    public var bypass = false
    public init(plugin: VST3Plugin, parameters: [VST3Parameter]) { self.plugin = plugin; self.parameters = parameters }
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

    @MainActor func prepare(rate: Double) throws {
        guard clap_vst3_prepare(effect, rate) != 0 else { throw VST3Error.message("This effect does not support offline stereo audio at this sample rate.") }
    }

    @MainActor func close() {
        guard !closed else { return }
        clap_vst3_effect_destroy(effect); clap_vst3_module_close(module); closed = true
    }
}
