import Foundation

/// Adds grain by modulating a short delay with a sine and filtered noise.
final class BuiltinErosion: @unchecked Sendable {
    static let defaults: [VST3Parameter] = [
        VST3Parameter(id: 0, name: "Frequency", value: 0.6, steps: 0),
        VST3Parameter(id: 1, name: "Amount", value: 0.4, steps: 0),
        VST3Parameter(id: 2, name: "Noise Blend", value: 0.5, steps: 0),
        VST3Parameter(id: 3, name: "Filter Width", value: 0.5, steps: 0),
        VST3Parameter(id: 4, name: "Stereo Width", value: 0, steps: 0)
    ]

    private let rate: Double
    private let maxDelay: Double
    private var delayL: [Float]
    private var delayR: [Float]
    private var writeIndex = 0
    private var phase = 0.0
    private var frequency = 0.6, amount = 0.4, blend = 0.5, width = 0.5, stereo = 0.0
    private var phaseStep = 0.0
    private var leftNoise = NoiseBand(seed: 0xB34D_51C2_67E9_A123)
    private var rightNoise = NoiseBand(seed: 0xA76C_9123_3BA5_C927)
    let tailFrames: Int

    init(sampleRate: Double, parameters: [VST3Parameter]) {
        let rate = sampleRate.isFinite && sampleRate >= 1_000 && sampleRate <= 384_000 ? sampleRate : 44_100
        self.rate = rate
        maxDelay = rate * 0.001
        tailFrames = Int(ceil(maxDelay)) + 1
        delayL = [Float](repeating: 0, count: tailFrames + 1)
        delayR = [Float](repeating: 0, count: tailFrames + 1)
        update(parameters: parameters)
    }

    func update(parameters: [VST3Parameter]) {
        for parameter in parameters {
            let v = parameter.value.isFinite ? min(1, max(0, parameter.value)) : 0
            switch parameter.id {
            case 0: frequency = v
            case 1: amount = v
            case 2: blend = v
            case 3: width = v
            case 4: stereo = v
            default: break
            }
        }
        let maxFrequency = min(18_000, rate * 0.45)
        let center = 200 * pow(maxFrequency / 200, frequency)
        phaseStep = 2 * .pi * center / rate
        let q = 10 * pow(0.035, width)
        leftNoise.configure(center: center, rate: rate, q: q)
        rightNoise.configure(center: center, rate: rate, q: q)
    }

    func process(left: inout [Float], right: inout [Float]) {
        guard left.count == right.count else { return }
        let size = delayL.count
        for i in left.indices {
            delayL[writeIndex] = left[i]
            delayR[writeIndex] = right[i]
            let sine = sin(phase)
            let sineR = sine + stereo * (cos(phase) - sine)
            let noiseL = leftNoise.next(), independentNoise = rightNoise.next()
            let noiseR = noiseL + stereo * (independentNoise - noiseL)
            let carrierL = sine * (1 - blend) + noiseL * blend
            let carrierR = sineR * (1 - blend) + noiseR * blend
            let offsetL = maxDelay * amount * (0.5 + 0.5 * carrierL)
            let offsetR = maxDelay * amount * (0.5 + 0.5 * carrierR)
            left[i] = sample(delayL, size: size, offset: offsetL)
            right[i] = sample(delayR, size: size, offset: offsetR)
            writeIndex = (writeIndex + 1) % size
            phase += phaseStep
            if phase >= 2 * .pi { phase -= 2 * .pi }
        }
    }

    private func sample(_ ring: [Float], size: Int, offset: Double) -> Float {
        let age = Int(offset)
        let fraction = Float(offset - Double(age))
        let recent = ring[(writeIndex - age + size) % size]
        let older = ring[(writeIndex - age - 1 + size) % size]
        return recent + (older - recent) * fraction
    }
}

private struct NoiseBand {
    var seed: UInt64
    private var b0 = 0.0, a1 = 0.0, a2 = 0.0, gain = 1.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(seed: UInt64) { self.seed = seed }

    mutating func configure(center: Double, rate: Double, q: Double) {
        let omega = 2 * Double.pi * center / rate
        let alpha = sin(omega) / (2 * q)
        let divisor = 1 + alpha
        b0 = alpha / divisor
        a1 = -2 * cos(omega) / divisor
        a2 = (1 - alpha) / divisor
        gain = min(8, 0.8 / sqrt(max(b0, 0.0001)))
    }

    mutating func next() -> Double {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        let white = Double(seed >> 40) / Double(1 << 23) - 1
        let y = b0 * (white - x2) - a1 * y1 - a2 * y2
        x2 = x1; x1 = white; y2 = y1; y1 = y
        return tanh(y * gain)
    }
}
