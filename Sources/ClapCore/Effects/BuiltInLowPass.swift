import Foundation

/// A resonant stereo low-pass for the effects chain.
final class BuiltInLowPass: BuiltInProcessor, @unchecked Sendable {
    static let defaultParameters = [
        VST3Parameter(id: 0, name: "Cutoff", value: 0.8, steps: 0),
        VST3Parameter(id: 1, name: "Resonance", value: 0, steps: 0),
        VST3Parameter(id: 2, name: "Slope", value: 0, steps: 1),
        VST3Parameter(id: 3, name: "Dry/Wet", value: 1, steps: 0)
    ]

    private struct Section {
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        var left1 = 0.0, left2 = 0.0, right1 = 0.0, right2 = 0.0

        mutating func set(cutoff: Double, q: Double, sampleRate: Double) {
            let omega = 2 * Double.pi * cutoff / sampleRate
            let cosine = cos(omega), alpha = sin(omega) / (2 * q), scale = 1 / (1 + alpha)
            b0 = (1 - cosine) * 0.5 * scale; b1 = (1 - cosine) * scale; b2 = b0
            a1 = -2 * cosine * scale; a2 = (1 - alpha) * scale
        }

        mutating func process(left: Double, right: Double) -> (Double, Double) {
            let outLeft = b0 * left + left1, outRight = b0 * right + right1
            left1 = b1 * left - a1 * outLeft + left2; left2 = b2 * left - a2 * outLeft
            right1 = b1 * right - a1 * outRight + right2; right2 = b2 * right - a2 * outRight
            return (outLeft, outRight)
        }
    }

    private let sampleRate: Double
    private var values = defaultParameters.map(\.value)
    private var first = Section(), second = Section()
    private var steep = false, wet = 1.0
    var tailFrames: Int { Int(sampleRate * 2) }

    init(sampleRate: Double, parameters: [VST3Parameter]) {
        self.sampleRate = sampleRate.isFinite && sampleRate >= 100 ? sampleRate : 44_100
        update(parameters: parameters)
    }

    func update(parameters: [VST3Parameter]) {
        for parameter in parameters where parameter.id < values.count {
            let index = Int(parameter.id)
            values[index] = parameter.value.isFinite ? min(1, max(0, parameter.value)) : Self.defaultParameters[index].value
        }
        let cutoff = min(20 * pow(1_000, values[0]), sampleRate * 0.45)
        let q = 0.7071067811865476 * pow(4, values[1])
        steep = values[2] >= 0.5; wet = values[3]
        // Two Butterworth sections give a flat passband at zero resonance.
        first.set(cutoff: cutoff, q: steep ? q * 0.7653668647 : q, sampleRate: sampleRate)
        second.set(cutoff: cutoff, q: q * 1.847759065, sampleRate: sampleRate)
    }

    func process(left: inout [Float], right: inout [Float]) {
        guard left.count == right.count else { return }
        for i in left.indices {
            let dryLeft = Double(left[i]), dryRight = Double(right[i])
            let filtered = first.process(left: dryLeft, right: dryRight)
            let filteredSteep = second.process(left: filtered.0, right: filtered.1)
            let result = steep ? filteredSteep : filtered
            left[i] = Float(dryLeft + wet * (result.0 - dryLeft))
            right[i] = Float(dryRight + wet * (result.1 - dryRight))
        }
    }
}
