import Foundation
import Testing
@testable import ClapCore

@Suite struct BuiltInHighPassTests {
    private let rate = 44_100.0

    private func parameters(cutoff: Double, resonance: Double = 0, steep: Bool = false, wet: Double = 1) -> [VST3Parameter] {
        [VST3Parameter(id: 0, name: "Cutoff", value: log(cutoff / 20) / log(1_000), steps: 0),
         VST3Parameter(id: 1, name: "Resonance", value: resonance, steps: 0),
         VST3Parameter(id: 2, name: "Slope", value: steep ? 1 : 0, steps: 1),
         VST3Parameter(id: 3, name: "Dry/Wet", value: wet, steps: 0)]
    }

    private func level(_ frequency: Double, steep: Bool = false, resonance: Double = 0) -> Double {
        let filter = BuiltInHighPass(sampleRate: rate, parameters: parameters(cutoff: 1_000, resonance: resonance, steep: steep))
        var left = (0..<8192).map { Float(sin(2 * .pi * frequency * Double($0) / rate)) }
        var right = left
        filter.process(left: &left, right: &right)
        return sqrt(left.suffix(4096).reduce(0.0) { $0 + Double($1 * $1) } / 4096)
    }

    @Test func letsHighFrequenciesThroughAndCutsLowFrequencies() {
        #expect(level(8_000) > 0.68, "A high tone should remain close to its original level")
        #expect(level(100) < 0.015, "A tone well below the cutoff should be attenuated")
        #expect(level(100, steep: true) < level(100) * 0.1, "The steeper slope should cut lows more strongly")
    }

    @Test func resonanceEmphasizesTheCutoff() {
        #expect(level(1_000, resonance: 0.7) > level(1_000) * 2, "Resonance raises the signal near cutoff")
    }

    @Test func preservesStereoAndBlockHistory() {
        let settings = parameters(cutoff: 2_000, resonance: 0.4)
        let one = BuiltInHighPass(sampleRate: rate, parameters: settings)
        let blocks = BuiltInHighPass(sampleRate: rate, parameters: settings)
        let input = (0..<1024).map { Float(sin(Double($0) * 0.25)) }
        var left = input, right = [Float](repeating: 0, count: input.count)
        one.process(left: &left, right: &right)
        var first = Array(input[..<512]), silentFirst = [Float](repeating: 0, count: 512)
        var second = Array(input[512...]), silentSecond = [Float](repeating: 0, count: 512)
        blocks.process(left: &first, right: &silentFirst)
        blocks.process(left: &second, right: &silentSecond)
        #expect(left == first + second, "Processing in blocks must preserve filter history")
        #expect(right.allSatisfy { $0 == 0 }, "One channel must not leak into the other")
    }

    @Test func dryMixAndUnsafeValuesStayFinite() {
        let filter = BuiltInHighPass(sampleRate: rate, parameters: parameters(cutoff: 500, wet: 0))
        var left: [Float] = [0.2, -0.4, 0.8], right = left
        let original = left
        filter.process(left: &left, right: &right)
        #expect(left == original && right == original, "Dry mix leaves both channels unchanged")
        filter.update(parameters: [VST3Parameter(id: 0, name: "Cutoff", value: .nan, steps: 0),
                                   VST3Parameter(id: 1, name: "Resonance", value: .infinity, steps: 0),
                                   VST3Parameter(id: 3, name: "Dry/Wet", value: 1, steps: 0)])
        filter.process(left: &left, right: &right)
        #expect((left + right).allSatisfy { $0.isFinite }, "Invalid settings must never create invalid audio")
    }
}
