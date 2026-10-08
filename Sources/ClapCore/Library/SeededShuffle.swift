import Foundation

/// A repeatable random order: the same seed always gives the same order for the same ids, and a new seed gives a
/// new one. Items keep their place relative to each other when others come and go, so a list does not jump around
/// when one sample is favourited or a file is added.
public enum SeededShuffle {
    /// SplitMix64 of the id mixed with the seed.
    public static func key(id: Int64, seed: UInt64) -> UInt64 {
        var z = UInt64(bitPattern: id) &+ seed &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public static func order<T>(_ items: [T], seed: UInt64, id: (T) -> Int64) -> [T] {
        items.map { (key(id: id($0), seed: seed), $0) }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }
}
