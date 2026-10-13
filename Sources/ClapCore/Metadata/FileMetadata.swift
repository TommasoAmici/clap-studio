import Foundation

/// What a file says about itself: the descriptive metadata sound libraries and recorders write into WAV files
/// (BWF `bext`, iXML, `LIST`/`INFO`) and the Universal Category System (UCS) naming of the file itself.
/// It is read, shown and searched; the app only writes the category and keywords, and only on request.
public struct FileMetadata: Equatable, Sendable {
    public var title = ""
    public var description = ""
    public var keywords: [String] = []
    /// The category the file names, in its own words (an `IGNR` genre, an iXML category, ...).
    public var category = ""
    public var subcategory = ""
    /// UCS category and subcategory in one, for example `DOORWood`.
    public var ucsID = ""
    public var creator = ""
    /// Library, product or recording source.
    public var source = ""
    /// Who or what made the file: the BWF originator or the software.
    public var originator = ""
    public var date = ""

    public init() {}

    public var isEmpty: Bool { self == FileMetadata() }

    /// Fills what is still empty from `other`, so the first source named keeps priority.
    mutating func fill(from other: FileMetadata) {
        if title.isEmpty { title = other.title }
        if description.isEmpty { description = other.description }
        if keywords.isEmpty { keywords = other.keywords }
        if category.isEmpty { category = other.category }
        if subcategory.isEmpty { subcategory = other.subcategory }
        if ucsID.isEmpty { ucsID = other.ucsID }
        if creator.isEmpty { creator = other.creator }
        if source.isEmpty { source = other.source }
        if originator.isEmpty { originator = other.originator }
        if date.isEmpty { date = other.date }
    }

    /// Keywords as separate, trimmed, distinct words from a list written with `;`, `,` or line breaks.
    public static func splitKeywords(_ text: String) -> [String] {
        var seen = Set<String>(), words: [String] = []
        for part in text.split(whereSeparator: { ";,\n\r|".contains($0) }) {
            let word = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty, word.count <= 60, seen.insert(word.lowercased()).inserted { words.append(word) }
            if words.count >= 60 { break }
        }
        return words
    }
}

/// UCS file names: `CatID(-UserCategory)_FXName_CreatorID_SourceID`, for example `DOORWood_Door Slam_BOOM_Library.wav`.
public enum UCSName {
    /// What the name carries, or nil when the file is not named that way. A CatID is a capitalised category
    /// followed by a subcategory (`DOORWood`, `AIRBrst`), and at least a creator must follow the FX name, which
    /// keeps names such as `KICK_Heavy_Sound` out.
    public static func parse(fileName: String) -> FileMetadata? {
        let stem = (fileName as NSString).deletingPathExtension
        let parts = stem.components(separatedBy: "_")
        guard parts.count >= 3, !Rx.matches(#"^[A-Z]{3,}[a-z][A-Za-z0-9]*(-[^_]+)?$"#, in: parts[0]).isEmpty else { return nil }
        var meta = FileMetadata()
        meta.ucsID = parts[0].components(separatedBy: "-")[0]
        // The second part may carry a vendor category in front of the name ("Vendor-Door Slam").
        var name = parts[1]
        if let dash = name.firstIndex(of: "-"), !name[..<dash].contains(" "), name[..<dash].count <= 24 {
            name = String(name[name.index(after: dash)...])
        }
        meta.title = name.trimmingCharacters(in: .whitespaces)
        meta.creator = parts[2].trimmingCharacters(in: .whitespaces)
        if parts.count > 3 { meta.source = parts[3].trimmingCharacters(in: .whitespaces) }
        return meta.title.isEmpty ? nil : meta
    }
}
