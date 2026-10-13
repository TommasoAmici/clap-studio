import Foundation

public struct GeoPoint: Sendable, Equatable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    public var text: String { String(format: "%.4f, %.4f", latitude, longitude) }
}

/// Regular-expression matches as plain strings: each match is its whole text followed by its groups ("" for a group that did not take part).
enum Rx {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var compiled: [String: NSRegularExpression] = [:]

    /// Patterns are compiled once; they are fixed strings in the code.
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options) -> NSRegularExpression? {
        lock.lock(); defer { lock.unlock() }
        let key = "\(options.rawValue):\(pattern)"
        if let found = compiled[key] { return found }
        let made = try? NSRegularExpression(pattern: pattern, options: options)
        compiled[key] = made
        return made
    }

    static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [[String]] {
        guard let regex = regex(pattern, options) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).map { match in
            (0..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}

/// Reading coordinates written the ways audio files and recorders write them.
public enum GeoParse {
    /// One coordinate: decimal degrees ("51.5", "-0.12", "51.5N"), degrees and decimal minutes ("51,30.5N", as in
    /// XMP), or degrees, minutes and seconds ("51°30'30\"N", "51 30 30 S"). A trailing or leading N/S/E/W sets the sign.
    public static func degrees(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let letters = trimmed.uppercased().filter { "NSEW".contains($0) }
        guard letters.count <= 1 else { return nil }
        let number = #"[-+]?\d+(?:\.\d+)?"#
        let numbers = Rx.matches(number, in: trimmed).compactMap { Double($0[0]) }
        guard (1...3).contains(numbers.count) else { return nil }
        // Anything else in the text must be separators or unit marks, not words ("12 apples").
        let rest = trimmed.replacingOccurrences(of: number, with: "", options: .regularExpression).uppercased()
            .filter { !" ,°'\"′″NSEW:;".contains($0) }
        guard rest.isEmpty else { return nil }
        var value = abs(numbers[0])
        if numbers.count > 1 { guard numbers[1] >= 0, numbers[1] < 60 else { return nil }; value += numbers[1] / 60 }
        if numbers.count > 2 { guard numbers[2] >= 0, numbers[2] < 60 else { return nil }; value += numbers[2] / 3600 }
        let negative = numbers[0] < 0 || trimmed.hasPrefix("-") || letters == "S" || letters == "W"
        return negative ? -value : value
    }

    /// A latitude and longitude as decimal text, or the pair as ISO 6709 ("+51.5000-000.1000/", the form MP4 and
    /// QuickTime files use; an altitude after them is ignored).
    public static func iso6709(_ text: String) -> GeoPoint? {
        guard let m = Rx.matches(#"^([+-]\d{1,2}(?:\.\d+)?)([+-]\d{1,3}(?:\.\d+)?)"#, in: text.trimmingCharacters(in: .whitespaces)).first,
              let lat = Double(m[1]), let lon = Double(m[2]) else { return nil }
        return GeoPoint(latitude: lat, longitude: lon)
    }

    /// A pair written as "51.5, -0.12" or "51.5N 0.12W".
    public static func pair(_ text: String) -> GeoPoint? {
        if let point = iso6709(text) { return point }
        let parts = text.split(whereSeparator: { $0 == ";" || $0 == "/" }).map(String.init)
        let halves = parts.count == 2 ? parts : text.components(separatedBy: ", ").count == 2 ? text.components(separatedBy: ", ") : []
        guard halves.count == 2, let lat = degrees(halves[0]), let lon = degrees(halves[1]) else { return nil }
        return GeoPoint(latitude: lat, longitude: lon)
    }
}
