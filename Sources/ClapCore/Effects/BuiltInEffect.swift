import Foundation

/// An effect supplied with Clap Studio, available alongside installed plug-ins.
public enum BuiltInEffect: String, CaseIterable, Codable, Sendable {
    case amplifier, lowPass, highPass, erosion

    public var name: String {
        switch self {
        case .amplifier: "Amplifier"
        case .lowPass: "Low-pass Filter"
        case .highPass: "High-pass Filter"
        case .erosion: "Erosion"
        }
    }

    public func makeSlot() -> EffectSlot {
        let plugin = VST3Plugin(bundle: URL(fileURLWithPath: "/clap-studio/built-in"), classID: rawValue, name: name, builtIn: self)
        switch self {
        case .amplifier: return EffectSlot(plugin: plugin, parameters: AmpProcessor.defaults)
        case .lowPass: return EffectSlot(plugin: plugin, parameters: BuiltInLowPass.defaultParameters)
        case .erosion: return EffectSlot(plugin: plugin, parameters: BuiltinErosion.defaults)
        case .highPass: return EffectSlot(plugin: plugin, parameters: BuiltInHighPass.defaultParameters)
        }
    }

    /// Show filter settings in their musical units; other controls use percentages.
    public func displayValue(for parameter: VST3Parameter) -> String? {
        guard self == .lowPass || self == .highPass, parameter.id == 0 || parameter.id == 2 else { return nil }
        let defaults = self == .lowPass ? BuiltInLowPass.defaultParameters : BuiltInHighPass.defaultParameters
        let raw = parameter.value.isFinite ? parameter.value : defaults[Int(parameter.id)].value
        let value = min(1, max(0, raw))
        return parameter.id == 0 ? SampleEdit.hertz(BuiltInFilter.cutoff(value).rounded()) : (value >= 0.5 ? "24 dB" : "12 dB")
    }

    func processor(sampleRate: Double, parameters: [VST3Parameter]) -> any BuiltInProcessor {
        switch self {
        case .amplifier: return AmpProcessor(sampleRate: sampleRate, parameters: parameters)
        case .lowPass: return BuiltInLowPass(sampleRate: sampleRate, parameters: parameters)
        case .erosion: return BuiltinErosion(sampleRate: sampleRate, parameters: parameters)
        case .highPass: return BuiltInHighPass(sampleRate: sampleRate, parameters: parameters)
        }
    }
}

/// Stateful stereo processing shared by auditions and bounces.
protocol BuiltInProcessor: AnyObject, Sendable {
    var tailFrames: Int { get }
    func update(parameters: [VST3Parameter])
    func process(left: inout [Float], right: inout [Float])
}
