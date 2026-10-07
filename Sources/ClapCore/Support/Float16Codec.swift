import Foundation

/// Compact on-disk encoding of embedding vectors.
public enum VectorCodec {
    public static func encodeFloat16(_ v: [Float]) -> Data {
        var out = [Float16](repeating: 0, count: v.count)
        for i in 0..<v.count { out[i] = Float16(v[i]) }
        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func decodeFloat16(_ d: Data) -> [Float] {
        let n = d.count / MemoryLayout<Float16>.size
        var out = [Float](repeating: 0, count: n)
        d.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: Float16.self)
            for i in 0..<n { out[i] = Float(p[i]) }
        }
        return out
    }

    public static func encodeFloat32(_ v: [Float]) -> Data {
        v.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func decodeFloat32(_ d: Data) -> [Float] {
        let n = d.count / MemoryLayout<Float>.size
        var out = [Float](repeating: 0, count: n)
        _ = out.withUnsafeMutableBytes { d.copyBytes(to: $0) }
        return out
    }
}

/// Small deterministic RNG so clustering and layout are reproducible.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}
