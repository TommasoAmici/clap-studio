import Foundation

/// Filters on measured properties, applied together with the sidebar and search filters.
public struct DescriptorFilter: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case any = "All", oneShot = "One-shots", loop = "Loops", fieldRecording = "Field recordings", joined = "Joined"
    }

    public var kind: Kind = .any
    public var bpmMin: Double?
    public var bpmMax: Double?
    /// Tonic such as "A" or "C#"; matches both note names ("A1") and keys ("A minor").
    public var tonic: String?
    public var category: String?
    /// A sample matches when it has any of these moods.
    public var moods: Set<String> = []

    public init() {}

    public var isActive: Bool { self != DescriptorFilter() }

    public mutating func reset() { self = DescriptorFilter() }

    public func matches(_ s: SampleRecord) -> Bool {
        switch kind {
        case .any: break
        // Field recordings are neither: they have no single tempo and are not played as one hit.
        case .oneShot: if s.isJoined || s.isLoop == true || s.isFieldRecording { return false }
        case .loop: if s.isJoined || s.isLoop != true || s.isFieldRecording { return false }
        case .fieldRecording: if s.isJoined || !s.isFieldRecording { return false }
        case .joined: if !s.isJoined { return false }
        }
        if bpmMin != nil || bpmMax != nil {
            guard let bpm = s.effectiveBPM else { return false }
            if let lo = bpmMin, bpm < lo { return false }
            if let hi = bpmMax, bpm > hi { return false }
        }
        if let tonic {
            guard let name = s.keyName, Self.tonic(of: name) == tonic else { return false }
        }
        // A field recording also matches the sounds heard in it (birds, water, ...).
        if let category, s.effectiveCategory != category, !s.sounds.contains(category) { return false }
        if !moods.isEmpty, moods.isDisjoint(with: s.moods) { return false }
        return true
    }

    /// "A1" -> "A", "C# major" -> "C#".
    public static func tonic(of keyName: String) -> String? {
        guard let first = keyName.first, first.isLetter else { return nil }
        var tonic = String(first)
        if keyName.dropFirst().first == "#" { tonic += "#" }
        return tonic
    }

    public static let tonics = NoteNames.sharps
}
