import Accelerate
import Foundation

/// The moods shown in the sidebar. Like the categories, each is described by a few phrases and scored with CLAP, but
/// a sound can have several moods, and a mood is judged relative to the library (see `MoodScorer.assign`).
///
/// The list comes from a prototype that scored 30 moods on a real library: moods CLAP could not tell apart
/// (Calm/Peaceful/Relaxed, Dark/Depressed/Scared, ...) were merged into one, and groups that stayed weak and
/// noise-like (Sad, Calm, Romantic) were dropped. Each phrase list below is the union of the merged moods' phrases.
public enum SoundMoods {
    /// Bumped whenever names or phrases change, so stored moods are recomputed.
    public static let version = "mood-v1"

    /// A mood is given to a sound when it scores this many standard deviations above the library's average.
    public static let threshold: Float = 1.5
    /// A sound keeps at most this many moods, strongest first.
    public static let maxPerSound = 3
    /// Below this many sounds the library's average is meaningless, so no moods are assigned.
    public static let minimumLibrary = 30

    public static let all: [(name: String, prompts: [String])] = [
        ("Aggressive", ["an angry, aggressive sound", "aggressive distorted music", "a furious growling sound",
                        "an enraged, violent sound", "furious screaming noise", "brutal explosive anger",
                        "a crazy, chaotic sound", "wild unhinged music", "a manic frantic noise"]),
        ("Rebellious", ["a rebellious, defiant sound", "raw punk attitude music", "a gritty, rough, rowdy sound"]),
        ("Powerful", ["a powerful, massive sound", "strong forceful music", "a hard-hitting, heavy impact",
                      "a confident, bold sound", "strong self-assured music", "a swaggering beat"]),
        ("Epic", ["an epic, cinematic sound", "huge dramatic orchestral music", "a heroic soaring theme"]),
        ("Dark", ["a dark, ominous sound", "dark moody music", "a menacing sinister atmosphere",
                  "a depressing, hopeless sound", "heavy sorrowful music", "a bleak numb atmosphere",
                  "a scary, frightening sound", "tense horror music", "a creepy, fearful atmosphere",
                  "a serious, grave sound", "solemn dramatic music", "a stern, intense atmosphere"]),
        ("Dreamy", ["a dreamy, floating sound", "ethereal dreamlike music", "a hazy shimmering atmosphere"]),
        ("Happy", ["a happy, joyful sound", "upbeat cheerful music", "a bright, bouncy melody",
                   "a playful, cheeky sound", "bouncy whimsical music", "a quirky, fun melody",
                   "a carefree, light-hearted sound", "cheerful easygoing music", "a breezy sunny tune"]),
        ("Uplifting", ["an uplifting, inspiring sound", "triumphant hopeful music", "a rising, energising melody",
                       "an emotional, moving sound", "heartfelt emotional music", "a tender, touching melody"]),
        ("Groovy", ["a groovy, funky sound", "a head-nodding groove", "smooth rhythmic funk music"]),
    ]

    public static var names: [String] { all.map(\.name) }

    /// Mood names in the canonical (sidebar) order; unknown names go last.
    public static func sorted(_ moods: [String]) -> [String] {
        let order = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        return moods.sorted { (order[$0] ?? .max, $0) < (order[$1] ?? .max, $1) }
    }

    /// SF Symbol for the sidebar.
    public static func symbol(for name: String) -> String {
        switch name {
        case "Aggressive": return "flame"
        case "Rebellious": return "bolt"
        case "Powerful": return "dumbbell"
        case "Epic": return "mountain.2"
        case "Dark": return "moon"
        case "Dreamy": return "moon.stars"
        case "Happy": return "sun.max"
        case "Uplifting": return "arrow.up.circle"
        case "Groovy": return "metronome"
        default: return "face.smiling"
        }
    }
}

/// Scores CLAP audio embeddings against the moods' phrases.
public final class MoodScorer: @unchecked Sendable {
    public struct Assignment: Sendable, Equatable {
        public let mood: Int          // index into `names`
        public let z: Float           // standard deviations above the library's average for this mood
    }

    public let names: [String]
    private let matrix: [Float]       // names.count × dim, rows L2-normalised
    private let dim: Int

    /// `embed` maps a phrase to a normalised vector (CLAP's text tower in the app).
    public init(embed: (String) throws -> [Float], moods: [(name: String, prompts: [String])] = SoundMoods.all) throws {
        var rows: [Float] = [], dim = 0
        for mood in moods {
            var mean: [Float] = []
            for prompt in mood.prompts {
                let v = try embed(prompt)
                if mean.isEmpty { mean = v; dim = v.count } else { vDSP.add(mean, v, result: &mean) }
            }
            l2Normalize(&mean)
            rows += mean
        }
        self.names = moods.map(\.name)
        self.matrix = rows
        self.dim = dim
    }

    /// Cosine score of each of `count` vectors (laid out back to back in `flat`) with each mood: count × names.count.
    public func rawScores(flat: [Float], count: Int) -> [Float] {
        let k = names.count
        guard count > 0, k > 0, flat.count == count * dim else { return [] }
        var scores = [Float](repeating: 0, count: count * k)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(count), Int32(k), Int32(dim),
                    1, flat, Int32(dim), matrix, Int32(dim), 0, &scores, Int32(k))
        return scores
    }

    /// How each mood scores across a set of sounds: the average and the spread of the raw cosine.
    public struct Statistics: Sendable, Equatable {
        public var mean: [Float]
        public var spread: [Float]
    }

    /// Statistics of `count` sounds' raw scores (count × names.count).
    public func statistics(raw: [Float], count: Int) -> Statistics {
        let k = names.count
        var mean = [Float](repeating: 0, count: k), spread = [Float](repeating: 1, count: k)
        guard count > 0, raw.count == count * k else { return Statistics(mean: mean, spread: spread) }
        for m in 0..<k {
            var sum: Float = 0, sumSquares: Float = 0
            for row in 0..<count { let v = raw[row * k + m]; sum += v; sumSquares += v * v }
            mean[m] = sum / Float(count)
            spread[m] = max((sumSquares / Float(count) - mean[m] * mean[m]).squareRoot(), 1e-6)
        }
        return Statistics(mean: mean, spread: spread)
    }

    /// Moods per sound from the raw scores of the whole library. Raw CLAP scores for moods are small and bunched
    /// together, so each mood is judged against the library: z = (score - mean) / standard deviation. A sound keeps
    /// its best moods (at most `maxPerSound`) whose z reaches `threshold`.
    public func assign(raw: [Float], count: Int) -> [[Assignment]] {
        guard count >= SoundMoods.minimumLibrary else { return [[Assignment]](repeating: [], count: count) }
        return assign(raw: raw, count: count, against: statistics(raw: raw, count: count))
    }

    /// Like `assign(raw:count:)`, but judged against statistics of other sounds. Used for the segments of field
    /// recordings, which must be compared with ordinary samples, not with each other.
    public func assign(raw: [Float], count: Int, against stats: Statistics) -> [[Assignment]] {
        let k = names.count
        guard k > 0, raw.count == count * k, stats.mean.count == k else {
            return [[Assignment]](repeating: [], count: count)
        }
        return (0..<count).map { row in
            (0..<k)
                .map { Assignment(mood: $0, z: (raw[row * k + $0] - stats.mean[$0]) / stats.spread[$0]) }
                .filter { $0.z >= SoundMoods.threshold }
                .sorted { $0.z > $1.z }
                .prefix(SoundMoods.maxPerSound)
                .map { $0 }
        }
    }
}
