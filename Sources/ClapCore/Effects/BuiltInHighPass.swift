import Foundation

/// A resonant stereo high-pass for the effects chain.
final class BuiltInHighPass: BuiltInFilter, @unchecked Sendable {
    static let defaultParameters = BuiltInFilter.defaults(cutoff: 0.35)

    init(sampleRate: Double, parameters: [VST3Parameter]) {
        super.init(sampleRate: sampleRate, parameters: parameters, highPass: true, defaults: Self.defaultParameters)
    }
}
