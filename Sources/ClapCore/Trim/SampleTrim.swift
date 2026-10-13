import Foundation

/// A non-destructive edit: the part of a file to use and how it sounds (see `SampleEdit`). The file itself is never
/// changed. A sample that is only edited has a trim that covers the whole file.
/// Positions are in seconds, so they do not depend on how the file is decoded.
public struct SampleTrim: Equatable, Sendable {
    public static let minimumLength = 0.01
    /// Always applied at both ends of a trimmed sound, to avoid clicks.
    public static let declick = 0.003

    public var start: Double
    public var end: Double
    /// Length of the fade at the end, on top of the always-on declick (0 for the declick only).
    public var fadeOut: Double
    public var edit: SampleEdit

    public init(start: Double, end: Double, fadeOut: Double = 0, edit: SampleEdit = SampleEdit()) {
        self.start = start; self.end = end; self.fadeOut = fadeOut; self.edit = edit
    }

    public var length: Double { end - start }
    public var effectiveFadeOut: Double { max(Self.declick, fadeOut) }

    /// The trim fitted to a file of `duration` seconds, or nil when too little would be left.
    public func clamped(toDuration duration: Double) -> SampleTrim? {
        guard duration > 0 else { return nil }
        let s = min(max(0, start), duration)
        let e = min(max(0, end), duration)
        guard e - s >= Self.minimumLength else { return nil }
        return SampleTrim(start: s, end: e, fadeOut: min(max(0, fadeOut), e - s), edit: edit.clamped())
    }

    /// True when it keeps the whole file with no extra fade.
    public func coversWholeFile(duration: Double) -> Bool {
        start <= 0.0005 && end >= duration - 0.0005 && fadeOut == 0
    }
}
