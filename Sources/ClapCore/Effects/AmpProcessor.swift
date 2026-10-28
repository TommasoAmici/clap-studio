import Foundation

/// A saturating amplifier with independent stereo tone filters.
final class AmpProcessor: BuiltInProcessor, @unchecked Sendable {
    static let defaults = [
        VST3Parameter(id: 0, name: "Drive", value: 0.4, steps: 0),
        VST3Parameter(id: 1, name: "Tone", value: 0.7, steps: 0),
        VST3Parameter(id: 2, name: "Output", value: 0.5, steps: 0),
        VST3Parameter(id: 3, name: "Dry/Wet", value: 1, steps: 0)
    ]
    let tailFrames = 0
    private let sampleRate: Double
    private var drive = 1.0, coefficient = 1.0, output = 1.0, mix = 1.0
    private var previousLeft = 0.0, previousRight = 0.0

    init(sampleRate: Double, parameters: [VST3Parameter]) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 44_100
        update(parameters: parameters)
    }

    func update(parameters: [VST3Parameter]) {
        func value(_ index: Int) -> Double {
            let raw = parameters.first(where: { $0.id == UInt32(index) })?.value ?? Self.defaults[index].value
            return raw.isFinite ? min(1, max(0, raw)) : Self.defaults[index].value
        }
        drive = 1 + 9 * value(0)
        let cutoff = min(sampleRate * 0.45, 800 * pow(12.5, value(1)))
        coefficient = 1 - exp(-2 * .pi * cutoff / sampleRate)
        output = 2 * value(2)
        mix = value(3)
    }

    func process(left: inout [Float], right: inout [Float]) {
        let normalization = tanh(drive)
        for index in left.indices {
            let dryLeft = Double(left[index]), dryRight = Double(right[index])
            let saturatedLeft = tanh(dryLeft * drive) / normalization
            let saturatedRight = tanh(dryRight * drive) / normalization
            previousLeft += coefficient * (saturatedLeft - previousLeft)
            previousRight += coefficient * (saturatedRight - previousRight)
            if mix > 0 {
                left[index] = Float(dryLeft * (1 - mix) + previousLeft * output * mix)
                right[index] = Float(dryRight * (1 - mix) + previousRight * output * mix)
            }
        }
    }
}
