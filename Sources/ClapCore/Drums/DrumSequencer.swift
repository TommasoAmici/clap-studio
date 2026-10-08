import Foundation

/// Step timing. A step is a sixteenth note; swing delays the odd ones.
public enum DrumTiming {
    public static let defaultBPM = 120.0

    public static func stepDuration(bpm: Double) -> Double { 60 / max(20, bpm) / 4 }

    /// Swing as drum machines show it: the share of each pair of steps taken by the first one.
    /// 50% is straight, 66.7% is a triplet feel, below 50% pushes the odd steps early.
    public static func swingPercent(_ swing: Double) -> Double { 50 + 50 * swing }
    public static func swing(percent: Double) -> Double { (percent - 50) / 50 }

    /// Seconds from the start of the bar to the start of `step` (0...15, then continuing into the next bar).
    public static func offset(ofStep step: Int, bpm: Double, swing: Double) -> Double {
        let d = stepDuration(bpm: bpm)
        return Double(step) * d + (step % 2 == 1 ? swing * d : 0)
    }

    /// Time from one step to the next, which differs from a plain step when swing is on.
    public static func interval(afterStep step: Int, bpm: Double, swing: Double) -> Double {
        offset(ofStep: step + 1, bpm: bpm, swing: swing) - offset(ofStep: step, bpm: bpm, swing: swing)
    }
}

/// What to play on one step.
public struct DrumEvent: Equatable, Sendable {
    public let time: Double        // seconds, on whatever clock `now` uses
    public let step: Int
    public let tracks: [Int]       // indices of the tracks that hit on this step
}

/// Turns a pattern and a clock into timed events, a little ahead of time so the audio engine can schedule them
/// exactly. Pure logic: the engine only maps events to sounds, so timing can be tested without audio.
public struct DrumSequencer: Sendable {
    public private(set) var step = 0
    public private(set) var nextTime: Double

    public init(startTime: Double) { nextTime = startTime }

    /// Events for every step that begins before `now + lookahead`. Tempo and swing are read each time, so
    /// changing them mid-bar takes effect from the next step. After a long stall, it resumes instead of racing to catch up.
    public mutating func advance(now: Double, lookahead: Double, bpm: Double, pattern: DrumPattern) -> [DrumEvent] {
        if nextTime < now - 0.05 { nextTime = now + 0.02 }
        let soloed = pattern.tracks.contains { $0.solo }
        var events: [DrumEvent] = []
        while nextTime < now + lookahead {
            let hits = pattern.tracks.indices.filter { i in
                let track = pattern.tracks[i]
                return track.hits[step] && !track.muted && (!soloed || track.solo)
            }
            events.append(DrumEvent(time: nextTime, step: step, tracks: hits))
            nextTime += DrumTiming.interval(afterStep: step, bpm: bpm, swing: pattern.swing)
            step = (step + 1) % DrumPattern.stepCount
        }
        return events
    }
}
