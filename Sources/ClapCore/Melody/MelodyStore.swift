import Foundation

/// Keeps the melody between launches in a file beside the library. A long melody has tens of thousands of notes, which
/// is too much for the app's small preferences, so it gets a file of its own.
public enum MelodyStore {
    /// `melody.json` next to the library (and so following `CLAP_DATA_DIR`).
    public static func defaultURL() throws -> URL {
        try LibraryStore.defaultURL().deletingLastPathComponent().appendingPathComponent("melody.json")
    }

    /// Writes the melody whole or not at all, so a crash half way never leaves a broken file behind.
    public static func save(_ pattern: MelodyPattern, to url: URL) throws {
        try JSONEncoder().encode(pattern).write(to: url, options: .atomic)
    }

    /// The saved melody, made safe to play; nil when there is none or the file cannot be read.
    public static func load(from url: URL) -> MelodyPattern? {
        guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(MelodyPattern.self, from: data) else { return nil }
        return saved.sanitized()
    }
}
