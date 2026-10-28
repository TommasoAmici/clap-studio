import Foundation

public enum JoinedLibrary {
    /// Marks published files in the current library without replacing later edits.
    public static func markJoined(in samples: inout [SampleRecord], pathsByRoot: [Int64: Set<String>]) -> [Int64] {
        var changed: [Int64] = []
        for index in samples.indices where !samples[index].isJoined {
            let sample = samples[index]
            if pathsByRoot[sample.rootID]?.contains(sample.relPath) == true {
                samples[index].isJoined = true
                changed.append(sample.id)
            }
        }
        return changed
    }
}
