import Foundation

/// A stretch of a recording, in seconds from its start.
public struct TimeSpan: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var length: Double { end - start }
    public init(start: Double, end: Double) { self.start = start; self.end = end }
}

/// Chops a long recording into the audible stretches between silences, so each can be embedded on its own.
public enum RecordingSegmenter {
    /// A quiet gap at least this long ends a segment.
    public static let minimumGapSeconds = 0.5
    /// Stretches shorter than this are noise, not events.
    public static let minimumSegmentSeconds = 0.25
    /// Longer stretches are split into equal pieces no longer than this (the model window).
    public static let maximumSegmentSeconds = 10.0
    /// Upper bound on segments per file; beyond it segments are sampled evenly.
    public static let maximumSegments = 400
    /// Context kept around each segment; the per-segment silence trim removes what is not needed.
    static let paddingSeconds = 0.1
    /// A recording whose loud and quiet parts differ by less than this has no silence to cut at, dB.
    static let minimumDynamicRangeDB: Float = 20
    /// Floor for the silence threshold, dBFS.
    static let thresholdFloorDB: Float = -70
    /// Margin above the noise floor (10th percentile of the envelope), dB.
    static let noiseMarginDB: Float = 8

    /// Segments of a recording given its loudness envelope (one dB value per `hop` seconds).
    public static func segments(envelopeDB: [Float], hop: Double, duration: Double) -> [TimeSpan] {
        guard !envelopeDB.isEmpty, hop > 0 else { return [] }
        let threshold = silenceThreshold(envelopeDB)
        let minGap = max(1, Int((minimumGapSeconds / hop).rounded(.up)))

        // Runs of audible windows separated by gaps of at least `minGap` quiet windows.
        var spans: [(first: Int, last: Int)] = []
        var first: Int?
        var lastLoud = 0
        var quiet = 0
        for (i, level) in envelopeDB.enumerated() {
            if level > threshold {
                if first == nil { first = i }
                lastLoud = i
                quiet = 0
            } else if let f = first {
                quiet += 1
                if quiet >= minGap { spans.append((f, lastLoud)); first = nil; quiet = 0 }
            }
        }
        if let f = first { spans.append((f, lastLoud)) }

        var result: [TimeSpan] = []
        for s in spans {
            let start = Double(s.first) * hop
            let end = Double(s.last + 1) * hop
            guard end - start >= minimumSegmentSeconds else { continue }
            let padded = TimeSpan(start: max(0, start - paddingSeconds), end: min(duration, end + paddingSeconds))
            result += split(padded)
        }
        return sampleEvenly(result, limit: maximumSegments)
    }

    /// Loudness below which a window counts as silence.
    static func silenceThreshold(_ envelopeDB: [Float]) -> Float {
        let sorted = envelopeDB.sorted()
        let p10 = sorted[min(sorted.count - 1, sorted.count / 10)]
        let p95 = sorted[min(sorted.count - 1, sorted.count * 95 / 100)]
        // Steady sound (rain, a machine) has no silence to cut at: the noise floor is the sound itself.
        if p95 - p10 < minimumDynamicRangeDB { return thresholdFloorDB }
        return max(p10 + noiseMarginDB, thresholdFloorDB)
    }

    private static func split(_ span: TimeSpan) -> [TimeSpan] {
        let pieces = max(1, Int((span.length / maximumSegmentSeconds).rounded(.up)))
        guard pieces > 1 else { return [span] }
        let step = span.length / Double(pieces)
        return (0..<pieces).map { TimeSpan(start: span.start + Double($0) * step, end: span.start + Double($0 + 1) * step) }
    }

    private static func sampleEvenly(_ spans: [TimeSpan], limit: Int) -> [TimeSpan] {
        guard spans.count > limit else { return spans }
        return (0..<limit).map { spans[$0 * spans.count / limit] }
    }
}
