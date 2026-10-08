import Accelerate
import Foundation

/// The sound categories shown in the sidebar. Each is described by a few phrases; CLAP places audio
/// near the phrases that describe it, so no training data is needed.
public enum SoundCategories {
    /// Bumped whenever names or phrases change, so stored categories are recomputed.
    public static let version = "cat-v2"

    public static let all: [(name: String, prompts: [String])] = [
        ("Kick", ["a kick drum", "a bass drum hit", "an 808 kick"]),
        ("Snare", ["a snare drum", "a snare hit", "a rimshot"]),
        ("Clap", ["a hand clap", "claps", "a clap drum machine sound"]),
        ("Hi-hat", ["a hi-hat", "a closed hi-hat", "an open hi-hat"]),
        ("Cymbal", ["a crash cymbal", "a ride cymbal", "a cymbal"]),
        ("Tom", ["a tom drum", "a floor tom", "tom drum hit"]),
        ("Percussion", ["percussion", "a shaker", "a tambourine", "congas and bongos"]),
        ("Drum Loop", ["a drum loop", "a drum beat", "a drum break"]),
        ("Bass", ["a bass sound", "a sub bass", "a bass guitar", "a synth bass"]),
        ("Synth", ["a synthesizer", "a synth chord", "an electronic synth sound"]),
        ("Lead", ["a synth lead", "a lead melody", "a solo lead synthesizer"]),
        ("Pad", ["a warm pad", "an ambient synth pad", "a sustained pad"]),
        ("Pluck", ["a pluck", "a plucked synth", "a short plucked note"]),
        ("Keys", ["a piano", "an electric piano", "an organ", "keyboard"]),
        ("Guitar", ["a guitar", "an electric guitar", "an acoustic guitar"]),
        ("Strings", ["strings", "a violin", "a cello", "an orchestra string section"]),
        ("Brass & Winds", ["brass", "a trumpet", "a saxophone", "a flute"]),
        ("Vocal", ["a human voice", "a vocal", "singing", "a spoken word"]),
        ("FX", ["a sound effect", "a riser", "an impact", "a sweep or whoosh"]),
        ("Ambience", ["an ambient atmosphere", "field recording", "background noise", "a drone texture"]),
    ]

    /// Long recordings. Not described by phrases: it is decided by duration (`FieldRecording.minimumSeconds`).
    public static let fieldRecording = FieldRecording.categoryName

    /// Every category in sidebar order.
    public static var names: [String] { all.map(\.name) + [fieldRecording] }
}

/// Zero-shot classifier over CLAP audio embeddings.
public final class Categorizer: @unchecked Sendable {
    public struct Result: Sendable, Equatable {
        public let category: String?     // nil when nothing is a clear match
        public let confidence: Float
    }

    /// Below this share of the softmax, a sound is left uncategorised rather than mislabelled.
    public static let minimumConfidence: Float = 0.25
    /// CLAP's learned logit scale; makes the softmax over cosines about as sharp as in training.
    static let temperature: Float = 100

    private let names: [String]
    private let matrix: [Float]      // names.count × dim, rows L2-normalised
    private let dim: Int

    /// `embed` maps a phrase to a normalised vector (CLAP's text tower in the app).
    public init(embed: (String) throws -> [Float], categories: [(name: String, prompts: [String])] = SoundCategories.all) throws {
        var rows: [Float] = [], dim = 0
        for category in categories {
            var mean: [Float] = []
            for prompt in category.prompts {
                let v = try embed(prompt)
                if mean.isEmpty { mean = v; dim = v.count } else { vDSP.add(mean, v, result: &mean) }
            }
            l2Normalize(&mean)
            rows += mean
        }
        self.names = categories.map(\.name)
        self.matrix = rows
        self.dim = dim
    }

    /// Classifies `count` vectors laid out back to back in `flat`.
    public func classify(flat: [Float], count: Int) -> [Result] {
        let k = names.count
        guard count > 0, k > 0, flat.count == count * dim else { return [] }
        var scores = [Float](repeating: 0, count: count * k)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(count), Int32(k), Int32(dim),
                    1, flat, Int32(dim), matrix, Int32(dim), 0, &scores, Int32(k))
        return (0..<count).map { row in
            let slice = scores[(row * k)..<((row + 1) * k)].map { $0 * Self.temperature }
            let top = slice.max() ?? 0
            let exps = slice.map { expf($0 - top) }
            let total = exps.reduce(0, +)
            let best = exps.indices.max { exps[$0] < exps[$1] } ?? 0
            let confidence = exps[best] / total
            return Result(category: confidence >= Self.minimumConfidence ? names[best] : nil, confidence: confidence)
        }
    }
}

extension SoundCategories {
    /// SF Symbol for the sidebar.
    public static func symbol(for name: String) -> String {
        switch name {
        case "Kick", "Tom": return "circle.circle"
        case "Snare", "Clap", "Percussion", "Drum Loop": return "scribble.variable"
        case "Hi-hat", "Cymbal": return "sparkle"
        case "Bass": return "waveform.path"
        case "Synth", "Lead", "Pad", "Pluck": return "pianokeys"
        case "Keys": return "pianokeys.inverse"
        case "Guitar", "Strings": return "guitars"
        case "Brass & Winds": return "wind"
        case "Vocal": return "mic"
        case "FX": return "wand.and.stars"
        case "Ambience": return "cloud"
        case "Field recording": return "leaf"
        default: return "tag"
        }
    }
}
