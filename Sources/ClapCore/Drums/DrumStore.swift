import Foundation

/// Keeps long drum patterns beside the library, outside the small UI preferences.
public enum DrumStore {
    public static func defaultURL() throws -> URL {
        try LibraryStore.defaultURL().deletingLastPathComponent().appendingPathComponent("drums.json")
    }

    public static func save(_ pattern: DrumPattern, to url: URL) throws {
        try JSONEncoder().encode(pattern).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) -> DrumPattern? {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(DrumPattern.self, from: data) else { return nil }
        return saved.sanitized()
    }
}
