import Foundation

/// A stereo room made from decaying reflections and diffusion delays.
final class BuiltInReverb: @unchecked Sendable {
    static let defaultParameters = [
        VST3Parameter(id: 0, name: "Predelay", value: 0.1, steps: 0),
        VST3Parameter(id: 1, name: "Size", value: 0.5, steps: 0),
        VST3Parameter(id: 2, name: "Decay", value: 0.5, steps: 0),
        VST3Parameter(id: 3, name: "Damping", value: 0.35, steps: 0),
        VST3Parameter(id: 4, name: "Stereo Width", value: 1, steps: 0),
        VST3Parameter(id: 5, name: "Dry/Wet", value: 0.35, steps: 0)
    ]

    /// The circular delay is allocated once; changing its length keeps existing history.
    private struct Delay {
        var samples: [Double]
        var position = 0
        var length: Int

        init(capacity: Int, length: Int = 1) {
            samples = [Double](repeating: 0, count: max(2, capacity))
            self.length = max(1, min(length, samples.count - 1))
        }

        mutating func setLength(_ frames: Int) { length = max(1, min(frames, samples.count - 1)) }
        func read() -> Double { samples[(position + samples.count - length) % samples.count] }
        mutating func write(_ value: Double) {
            samples[position] = value
            position = (position + 1) % samples.count
        }
    }

    private struct Comb {
        var delay: Delay
        var baseSeconds: Double
        var feedback = 0.0
        var filtered = 0.0

        init(baseSeconds: Double, sampleRate: Double) {
            self.baseSeconds = baseSeconds
            delay = Delay(capacity: Int(ceil(baseSeconds * 1.5 * sampleRate)) + 2)
        }

        mutating func update(size: Double, decay: Double, sampleRate: Double) {
            let frames = max(1, Int((baseSeconds * size * sampleRate).rounded()))
            delay.setLength(frames)
            feedback = pow(0.001, Double(delay.length) / sampleRate / decay)
        }

        mutating func process(_ input: Double, damping: Double) -> Double {
            let output = delay.read()
            filtered = output * (1 - damping) + filtered * damping
            delay.write(input + filtered * feedback)
            return output
        }
    }

    private struct Diffuser {
        var delay: Delay
        init(seconds: Double, sampleRate: Double) {
            let frames = max(1, Int((seconds * sampleRate).rounded()))
            delay = Delay(capacity: frames + 1, length: frames)
        }
        mutating func process(_ input: Double) -> Double {
            let delayed = delay.read(), output = delayed - 0.5 * input
            delay.write(input + 0.5 * output)
            return output
        }
    }

    private let sampleRate: Double
    private var predelayLeft: Delay, predelayRight: Delay
    private var leftCombs: [Comb], rightCombs: [Comb]
    private var leftDiffusers: [Diffuser], rightDiffusers: [Diffuser]
    private var predelayFrames = 0, damping = 0.0, width = 1.0, wet = 0.35
    private(set) var tailFrames = 0

    init(sampleRate: Double, parameters: [VST3Parameter]) {
        let rate = sampleRate.isFinite && (1_000...384_000).contains(sampleRate) ? sampleRate : 44_100
        self.sampleRate = rate
        predelayLeft = Delay(capacity: Int(ceil(rate * 0.1)) + 2)
        predelayRight = Delay(capacity: Int(ceil(rate * 0.1)) + 2)
        let times = [0.0297, 0.0371, 0.0411, 0.0437]
        leftCombs = times.map { Comb(baseSeconds: $0, sampleRate: rate) }
        rightCombs = times.map { Comb(baseSeconds: $0 * 1.031, sampleRate: rate) }
        leftDiffusers = [0.005, 0.0017].map { Diffuser(seconds: $0, sampleRate: rate) }
        rightDiffusers = [0.0053, 0.0019].map { Diffuser(seconds: $0, sampleRate: rate) }
        update(parameters: parameters)
    }

    func update(parameters: [VST3Parameter]) {
        func value(_ index: Int) -> Double {
            let raw = parameters.first(where: { $0.id == UInt32(index) })?.value ?? Self.defaultParameters[index].value
            return raw.isFinite ? min(1, max(0, raw)) : Self.defaultParameters[index].value
        }
        let predelay = value(0) * 0.1
        predelayFrames = Int((predelay * sampleRate).rounded())
        predelayLeft.setLength(predelayFrames); predelayRight.setLength(predelayFrames)
        let size = 0.55 + 0.9 * value(1)
        let decay = 0.25 * pow(32, value(2))
        damping = 0.8 * value(3); width = value(4); wet = value(5)
        for index in leftCombs.indices {
            leftCombs[index].update(size: size, decay: decay, sampleRate: sampleRate)
            rightCombs[index].update(size: size, decay: decay, sampleRate: sampleRate)
        }
        // Allow the diffusion stages to finish after the nominal -60 dB decay.
        tailFrames = Int(ceil(min(10, predelay + decay + 0.2) * sampleRate))
    }

    func process(left: inout [Float], right: inout [Float]) {
        guard left.count == right.count else { return }
        for index in left.indices {
            let dryLeft = Double(left[index]), dryRight = Double(right[index])
            let inputLeft = predelayFrames == 0 ? dryLeft : predelayLeft.read()
            let inputRight = predelayFrames == 0 ? dryRight : predelayRight.read()
            predelayLeft.write(dryLeft); predelayRight.write(dryRight)
            var outputLeft = 0.0, outputRight = 0.0
            for i in leftCombs.indices {
                outputLeft += leftCombs[i].process(inputLeft * 0.25, damping: damping)
                outputRight += rightCombs[i].process(inputRight * 0.25, damping: damping)
            }
            for i in leftDiffusers.indices {
                outputLeft = leftDiffusers[i].process(outputLeft)
                outputRight = rightDiffusers[i].process(outputRight)
            }
            let mid = (outputLeft + outputRight) * 0.5
            let side = (outputLeft - outputRight) * 0.5 * width
            if wet > 0 {
                left[index] = Float(dryLeft * (1 - wet) + (mid + side) * wet)
                right[index] = Float(dryRight * (1 - wet) + (mid - side) * wet)
            }
        }
    }
}
