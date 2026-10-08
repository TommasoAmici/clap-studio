import Foundation

/// File names for exported copies, built from a template such as "{category} - {name} - {bpm}".
///
/// Tokens: `{name}` `{folder}` `{category}` `{bpm}` `{key}` `{tags}` `{n}` (position, zero-padded).
/// A token with no value (a one-shot has no BPM) disappears together with the separators around it.
public enum ExportNaming {
    public static let defaultTemplate = "{name}"
    public static let tokens = ["name", "folder", "category", "bpm", "key", "tags", "n"]

    public static func fileName(template: String, for sample: SampleRecord, position: Int, of total: Int) -> String {
        let width = max(2, String(total).count)
        let values: [String: String] = [
            "name": sample.name,
            "folder": (sample.folder as NSString).lastPathComponent,
            "category": sample.effectiveCategory ?? "",
            "bpm": sample.effectiveBPM.map { String(Int($0.rounded())) } ?? "",
            "key": sample.keyName ?? "",
            "tags": sample.tags.joined(separator: " "),
            "n": String(format: "%0\(width)d", position),
        ]
        var text = template.isEmpty ? defaultTemplate : template
        for (token, value) in values { text = text.replacingOccurrences(of: "{\(token)}", with: value) }
        let stem = tidy(sanitize(text))
        let finalStem = stem.isEmpty ? sanitize(sample.name) : stem
        return sample.ext.isEmpty ? finalStem : "\(finalStem).\(sample.ext)"
    }

    /// Removes characters that are unsafe in file names ("/" ":" and control characters) and leading dots.
    static func sanitize(_ text: String) -> String {
        let cleaned = text.unicodeScalars.map { scalar -> Character in
            scalar == "/" || scalar == ":" || scalar == "\\" || CharacterSet.controlCharacters.contains(scalar) ? "-" : Character(scalar)
        }
        return String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// Collapses what empty tokens leave behind: doubled separators, dangling dashes, extra spaces.
    static func tidy(_ text: String) -> String {
        var result = text
        // " - - " (an empty token between two separators) becomes " - "; runs of spaces become one.
        for (pattern, replacement) in [(#"(\s[-_–]\s)(\s*[-_–]\s)+"#, "$1"), (#"\s{2,}"#, " "), (#"-{2,}"#, "-")] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                        withTemplate: replacement)
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " -_–"))
    }
}
