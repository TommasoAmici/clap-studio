#if NON_COMMERCIAL
import Foundation

/// One of BirdNET's species outputs.
public struct BirdSpecies: Sendable, Hashable {
    public let scientific: String
    public let common: String
}

/// The names of BirdNET's 6,522 outputs, in model order (`tools/export_birdnet.py` writes `birdnet_labels.txt`).
/// A few outputs are not birds (frogs, bats, human sounds); they are kept, since the model reports them.
public struct BirdLabels: Sendable {
    public let species: [BirdSpecies]
    private let indexByScientific: [String: Int]

    public init(species: [BirdSpecies]) {
        self.species = species
        var map: [String: Int] = [:]
        for (i, s) in species.enumerated() { map[s.scientific] = i }
        indexByScientific = map
    }

    /// Lines of "Scientific name_Common name".
    public init(text: String) {
        var parsed: [BirdSpecies] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let split = line.firstIndex(of: "_") else { continue }
            parsed.append(BirdSpecies(scientific: String(line[..<split]),
                                      common: String(line[line.index(after: split)...])))
        }
        self.init(species: parsed)
    }

    public static func load() -> BirdLabels? {
        guard let url = ModelLocator.resource("birdnet_labels.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let labels = BirdLabels(text: text)
        return labels.species.isEmpty ? nil : labels
    }

    public func index(ofScientific name: String) -> Int? { indexByScientific[name] }
}
#endif
