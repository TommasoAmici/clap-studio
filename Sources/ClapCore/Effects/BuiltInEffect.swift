import Foundation

/// An effect supplied with Clap Studio, available alongside installed plug-ins.
public enum BuiltInEffect: String, CaseIterable, Codable, Sendable {
    case amplifier, lowPass, erosion

    public var name: String {
        switch self {
        case .amplifier: "Amplifier"
        case .lowPass: "Low-pass Filter"
        case .erosion: "Erosion"
        }
    }

    public func makeSlot() -> EffectSlot {
        let plugin = VST3Plugin(bundle: URL(fileURLWithPath: "/clap-studio/built-in"), classID: rawValue, name: name, builtIn: self)
        switch self {
        case .amplifier: return EffectSlot(plugin: plugin, parameters: AmpProcessor.defaults)
        case .lowPass: return EffectSlot(plugin: plugin, parameters: BuiltInLowPass.defaultParameters)
        case .erosion: return EffectSlot(plugin: plugin, parameters: BuiltinErosion.defaults)
        }
    }

    func processor(sampleRate: Double, parameters: [VST3Parameter]) -> any BuiltInProcessor {
        switch self {
        case .amplifier: return AmpProcessor(sampleRate: sampleRate, parameters: parameters)
        case .lowPass: return BuiltInLowPass(sampleRate: sampleRate, parameters: parameters)
        case .erosion: return BuiltinErosion(sampleRate: sampleRate, parameters: parameters)
        }
    }
}

/// Stateful stereo processing shared by auditions and bounces.
protocol BuiltInProcessor: AnyObject, Sendable {
    var tailFrames: Int { get }
    func update(parameters: [VST3Parameter])
    func process(left: inout [Float], right: inout [Float])
}
