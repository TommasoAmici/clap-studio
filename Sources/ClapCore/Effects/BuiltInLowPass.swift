import Foundation

/// A resonant stereo low-pass for the effects chain.
final class BuiltInLowPass: BuiltInFilter, @unchecked Sendable {
    static let defaultParameters = BuiltInFilter.defaults(cutoff: 0.8)

    init(sampleRate: Double, parameters: [VST3Parameter]) {
        super.init(sampleRate: sampleRate, parameters: parameters, highPass: false, defaults: Self.defaultParameters)
    }
}
