import Foundation

/// One species heard in one 3 s stretch of a recording.
public struct BirdDetection: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let scientific: String
    public let common: String
    public let confidence: Float

    public init(start: Double, end: Double, scientific: String, common: String, confidence: Float) {
        self.start = start
        self.end = end
        self.scientific = scientific
        self.common = common
        self.confidence = confidence
    }
}

/// Runs BirdNET over a long recording, 3 s at a time. Everything above `candidateFloor` is kept, so the confidence
/// and location cut-offs can change later without listening again.
public final class BirdDetector: @unchecked Sendable {
    public static let windowSeconds = 3.0
    /// Detections below this are not stored.
    public static let candidateFloor: Float = 0.1
    /// At most this many species per window are stored.
    public static let perWindowLimit = 5
    /// The shortest final stretch that is still listened to (it is padded with silence).
    public static let shortestWindow = 1.0
    /// Audio decoded at a time; whole windows only.
    static let blockSeconds = 60.0

    private let classifier: BirdClassifier
    private let labels: BirdLabels

    public init(classifier: BirdClassifier, labels: BirdLabels) {
        self.classifier = classifier
        self.labels = labels
    }

    /// BirdNET's sigmoid on a logit (sensitivity 1).
    static func probability(_ logit: Float) -> Float { 1 / (1 + exp(-min(15, max(-15, logit)))) }

    /// Detections for one window's logits: best first, at most `perWindowLimit`, none below `candidateFloor`.
    /// With `allowed`, species that do not occur at the recording's place are dropped before the limit applies.
    func candidates(from logits: [Float], start: Double, end: Double, allowed: Set<String>? = nil) -> [BirdDetection] {
        var best: [(index: Int, p: Float)] = []
        for (i, logit) in logits.enumerated() where i < labels.species.count {
            let p = Self.probability(logit)
            guard p >= Self.candidateFloor else { continue }
            if let allowed, !allowed.contains(labels.species[i].scientific) { continue }
            best.append((i, p))
        }
        best.sort { $0.p > $1.p }
        return best.prefix(Self.perWindowLimit).map {
            BirdDetection(start: start, end: end, scientific: labels.species[$0.index].scientific,
                          common: labels.species[$0.index].common, confidence: $0.p)
        }
    }

    /// Nil when cancelled part-way: nothing should be stored then.
    public func detect(url: URL, duration: Double, allowed: Set<String>? = nil,
                       isCancelled: @Sendable () -> Bool = { false }) throws -> [BirdDetection]? {
        let rate = BirdClassifier.sampleRate
        let window = BirdClassifier.windowSamples
        var found: [BirdDetection] = []
        var blockStart = 0.0
        while blockStart < duration {
            if isCancelled() { return nil }
            let audio = try AudioDecoder.decode(url: url, start: blockStart, seconds: Self.blockSeconds, sampleRate: rate)
            if audio.isEmpty { break }
            var offset = 0
            while offset < audio.count {
                let count = min(window, audio.count - offset)
                defer { offset += window }
                if Double(count) / rate < Self.shortestWindow { break }
                let slice = Array(audio[offset..<(offset + count)])
                if slice.allSatisfy({ abs($0) < 1e-6 }) { continue }    // digital silence says nothing
                let start = blockStart + Double(offset) / rate
                found += candidates(from: try classifier.logits(slice), start: start,
                                    end: min(duration, start + Self.windowSeconds), allowed: allowed)
                if isCancelled() { return nil }
            }
            blockStart += Self.blockSeconds
        }
        return found
    }
}
