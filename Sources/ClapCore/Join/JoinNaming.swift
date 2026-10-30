import Foundation

/// File names for joined samples: `<name> 01.wav`, `<name> 02.wav`, and so on.
public enum JoinNaming {
    public static let defaultName = "Joined"
    /// Keeps `<name> 100.wav` (and a "2" added for a clash) far inside what a file system accepts.
    public static let maxNameLength = 100

    /// What the musician typed, made safe as the start of a file name; empty or unusable text becomes "Joined".
    public static func baseName(_ typed: String) -> String {
        let cleaned = ExportNaming.sanitize(typed.trimmingCharacters(in: .whitespacesAndNewlines))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? defaultName : String(cleaned.prefix(maxNameLength))
    }

    /// One leading zero ("01"), and the natural width from 100 on.
    public static func fileName(base: String, number: Int) -> String {
        "\(base) \(String(format: "%02d", number)).wav"
    }
}
