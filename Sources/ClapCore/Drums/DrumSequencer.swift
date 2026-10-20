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

    /// Like `offset(ofStep:)` for a place between steps (2.5 is half way through step 2), which keeps the swing.
    public static func offset(ofPosition position: Double, bpm: Double, swing: Double) -> Double {
        let step = Int(position.rounded(.down))
        let into = position - Double(step)
        return offset(ofStep: step, bpm: bpm, swing: swing) + into * interval(afterStep: step, bpm: bpm, swing: swing)
    }
}

/// A melody note to start, with its time and length in seconds on the same clock as the drum hits.
public struct NoteHit: Equatable, Sendable {
    public let track: Int
    public let pitch: Int
    public let time: Double
    public let duration: Double
    public let velocity: Float
}

/// What to play on one step.
public struct DrumEvent: Equatable, Sendable {
    public let time: Double        // seconds, on whatever clock `now` uses
    public let step: Int
    public let tracks: [Int]       // indices of the tracks that hit on this step
    /// Melody notes that start during this step.
    public var notes: [NoteHit] = []
    /// Where this step falls in the melody's loop (0 up to the pattern's length), for its playhead.
    public var melodyStep = 0
}

/// Turns the drum pattern, the melody and a clock into timed events, a little ahead of time so the audio engine can
/// schedule them exactly. Pure logic: the engine only maps events to sounds, so timing can be tested without audio.
/// Drums and melody share one step counter, so they stay together however long the melody is.
public struct DrumSequencer: Sendable {
    /// Which step of the bar is next (0...15).
    public var step: Int { tick % DrumPattern.stepCount }
    public private(set) var nextTime: Double
    private var tick = 0

    public init(startTime: Double) { nextTime = startTime }

    /// Events for every step that begins before `now + lookahead`. Tempo and swing are read each time, so
    /// changing them mid-bar takes effect from the next step. After a long stall, it resumes instead of racing to catch up.
    public mutating func advance(now: Double, lookahead: Double, bpm: Double, pattern: DrumPattern,
                                 melody: MelodyPattern = MelodyPattern()) -> [DrumEvent] {
        if nextTime < now - 0.05 { nextTime = now + 0.02 }
        let soloed = pattern.tracks.contains { $0.solo } || melody.tracks.contains { $0.solo }
        let loop = max(DrumPattern.stepCount, melody.stepCount)
        var events: [DrumEvent] = []
        while nextTime < now + lookahead {
            tick %= loop                                    // a shorter melody can leave the counter past its end
            let hits = pattern.tracks.indices.filter { i in
                let track = pattern.tracks[i]
                return track.hits[step] && !track.muted && (!soloed || track.solo)
            }
            var event = DrumEvent(time: nextTime, step: step, tracks: hits)
            event.melodyStep = tick
            event.notes = notes(startingAt: tick, stepTime: nextTime, bpm: bpm, swing: pattern.swing, melody: melody, soloed: soloed)
            events.append(event)
            nextTime += DrumTiming.interval(afterStep: step, bpm: bpm, swing: pattern.swing)
            tick = (tick + 1) % loop
        }
        return events
    }

    private func notes(startingAt position: Int, stepTime: Double, bpm: Double, swing: Double,
                       melody: MelodyPattern, soloed: Bool) -> [NoteHit] {
        var hits: [NoteHit] = []
        let from = Double(position), to = from + 1
        for (index, track) in melody.tracks.enumerated() where !track.muted && (!soloed || track.solo) {
            for note in track.notes where note.start >= from && note.start < to {
                let begin = DrumTiming.offset(ofPosition: note.start, bpm: bpm, swing: swing)
                let end = DrumTiming.offset(ofPosition: note.end, bpm: bpm, swing: swing)
                let stepStart = DrumTiming.offset(ofStep: position, bpm: bpm, swing: swing)
                hits.append(NoteHit(track: index, pitch: note.pitch, time: stepTime + (begin - stepStart),
                                    duration: end - begin, velocity: note.velocity))
            }
        }
        return hits
    }
}
