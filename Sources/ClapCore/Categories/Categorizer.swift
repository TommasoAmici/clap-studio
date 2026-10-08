import Accelerate
import Foundation

/// The sound categories shown in the sidebar. Each is described by a few phrases; CLAP places audio
/// near the phrases that describe it, so no training data is needed.
public enum SoundCategories {
    /// Bumped whenever names or phrases change, so stored categories are recomputed.
    public static let version = "cat-v3"

    /// Musical categories.
    public static let musical: [(name: String, prompts: [String])] = [
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

    /// Bumped whenever the sounds named in field recordings (vocabulary, phrases, cut-offs) change.
    public static let soundsVersion = "sounds-v1"

    /// Sound names in the canonical (sidebar) order; unknown names go last.
    public static func sortedSounds(_ sounds: [String]) -> [String] {
        let order = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        return sounds.sorted { (order[$0] ?? .max, $0) < (order[$1] ?? .max, $1) }
    }

    /// Sounds of the world outside the studio. Ordinary samples (a single bird call) can have these categories, and
    /// they are what the segments of a field recording are named with.
    public static let environment: [(name: String, prompts: [String])] = [
        ("Birds", ["birds singing", "a bird chirping", "birdsong in the morning"]),
        ("Water", ["flowing water", "a stream or river", "waves on a shore", "a water fountain"]),
        ("Rain", ["rain falling", "raindrops on a roof", "a heavy rain shower"]),
        ("Wind", ["wind blowing", "a strong wind howling", "wind in the trees"]),
        ("Thunder", ["thunder rumbling", "a thunderstorm"]),
        ("Fire", ["a crackling fire", "flames burning", "a campfire"]),
        ("Insects", ["insects buzzing", "crickets chirping", "cicadas", "a fly buzzing"]),
        ("Animals", ["a dog barking", "an animal calling", "cows and sheep", "frogs croaking"]),
        ("Speech", ["people speaking", "a person talking", "a conversation", "a voice announcing"]),
        ("Crowd", ["a crowd of people", "a busy crowd murmuring", "people cheering", "children playing"]),
        ("Footsteps", ["footsteps", "someone walking on gravel", "steps on a wooden floor"]),
        ("Traffic", ["traffic noise", "cars passing on a road", "a busy street", "a car horn"]),
        ("Aircraft", ["an airplane flying overhead", "a helicopter", "a jet engine"]),
        ("Trains", ["a train passing", "a train on tracks", "a subway arriving"]),
        ("Machinery", ["machinery running", "an engine humming", "a motor", "a factory"]),
        ("Bells", ["church bells ringing", "a bell chiming", "wind chimes"]),
    ]

    /// Every category that phrases describe, in sidebar order.
    public static var all: [(name: String, prompts: [String])] { musical + environment }

    /// What the segments of a field recording are scored against: every category except the catch-alls.
    public static var segmentVocabulary: [(name: String, prompts: [String])] {
        all.filter { !["Ambience", "FX"].contains($0.name) }
    }

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

    public struct Label: Sendable, Equatable {
        public let name: String
        public let confidence: Float
    }

    /// Up to `limit` best categories per vector whose softmax share reaches `minimum`, best first. For segments
    /// of field recordings, which often hold more than one sound.
    public func classifyTop(flat: [Float], count: Int, limit: Int = 2, minimum: Float = 0.2) -> [[Label]] {
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
            return exps.indices
                .map { Label(name: names[$0], confidence: exps[$0] / total) }
                .filter { $0.confidence >= minimum }
                .sorted { $0.confidence > $1.confidence }
                .prefix(limit).map { $0 }
        }
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
        case "Birds": return "bird"
        case "Water": return "water.waves"
        case "Rain": return "cloud.rain"
        case "Wind": return "wind"
        case "Thunder": return "cloud.bolt"
        case "Fire": return "flame"
        case "Insects": return "ant"
        case "Animals": return "pawprint"
        case "Speech": return "person.wave.2"
        case "Crowd": return "person.3"
        case "Footsteps": return "figure.walk"
        case "Traffic": return "car"
        case "Aircraft": return "airplane"
        case "Trains": return "tram"
        case "Machinery": return "gearshape.2"
        case "Bells": return "bell"
        default: return "tag"
        }
    }
}
