import AVFoundation
import Foundation

/// The tuned sounds the melody needs: for each track's sample, one copy per tuning its notes use, made in the
/// background so the melody can be edited while it plays. Anything no note needs any more is let go.
public final class MelodySounds: @unchecked Sendable {
    /// Samples are read up to this long: a melody instrument is short, and many tunings are kept at once.
    static let maxSeconds = 20.0

    private struct Key: Hashable { let sampleID: Int64; let semitones: Int }
    private struct Entry { let source: DrumSource; let buffer: AVAudioPCMBuffer }

    private let cache: AudioBufferCache
    private let queue = DispatchQueue(label: "clap.melody.decode", qos: .userInitiated)
    private let lock = NSLock()
    private var sources: [Int64: DrumSource] = [:]
    private var ready: [Key: Entry] = [:]
    private var inFlight: [Key: DrumSource] = [:]         // being made, and from which file

    public init(cache: AudioBufferCache) { self.cache = cache }

    /// Says which sounds the melody now uses and where they are; starts making the tunings that are missing.
    public func update(melody: MelodyPattern, sources newSources: [Int64: DrumSource]) {
        var needed: [Int64: Set<Int>] = [:]
        for track in melody.tracks {
            guard let id = track.sampleID, newSources[id] != nil else { continue }
            for note in track.notes { needed[id, default: []].insert(MelodyVoice.semitones(note: note.pitch, root: track.rootNote)) }
        }
        lock.lock()
        sources = newSources
        ready = ready.filter { key, entry in needed[key.sampleID]?.contains(key.semitones) == true && newSources[key.sampleID] == entry.source }
        var work: [(id: Int64, source: DrumSource, tunings: [Int])] = []
        for (id, tunings) in needed {
            guard let source = newSources[id] else { continue }
            let missing = tunings.filter { ready[Key(sampleID: id, semitones: $0)] == nil && inFlight[Key(sampleID: id, semitones: $0)] != source }
            guard !missing.isEmpty else { continue }
            for t in missing { inFlight[Key(sampleID: id, semitones: t)] = source }
            work.append((id, source, missing.sorted()))
        }
        lock.unlock()
        for item in work { queue.async { [weak self] in self?.prepare(id: item.id, source: item.source, tunings: item.tunings) } }
    }

    /// The sample tuned by `semitones`, once it is ready.
    public func buffer(sampleID: Int64, semitones: Int) -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        return ready[Key(sampleID: sampleID, semitones: semitones)]?.buffer
    }

    /// The sample tuned by `semitones`, made now if no note needed it yet (so a piano key can be heard before any note
    /// is written). This reads the file, so call it off the main thread. nil when the melody does not know the sound.
    public func sound(sampleID: Int64, semitones: Int) -> AVAudioPCMBuffer? {
        lock.lock()
        if let entry = ready[Key(sampleID: sampleID, semitones: semitones)] { lock.unlock(); return entry.buffer }
        let source = sources[sampleID]
        lock.unlock()
        guard let source, let base = Self.read(source, cache: cache) else { return nil }
        let tuned = MelodyVoice.pitched(base, semitones: semitones)
        lock.lock(); defer { lock.unlock() }
        if sources[sampleID] == source { ready[Key(sampleID: sampleID, semitones: semitones)] = Entry(source: source, buffer: tuned) }
        return tuned
    }

    private func prepare(id: Int64, source: DrumSource, tunings: [Int]) {
        let base = Self.read(source, cache: cache)
        lock.lock()
        for t in tunings where inFlight[Key(sampleID: id, semitones: t)] == source { inFlight[Key(sampleID: id, semitones: t)] = nil }
        lock.unlock()
        guard let base else { return }
        for t in tunings {
            let tuned = MelodyVoice.pitched(base, semitones: t)
            lock.lock()
            if sources[id] == source { ready[Key(sampleID: id, semitones: t)] = Entry(source: source, buffer: tuned) }
            lock.unlock()
        }
    }

    private static func read(_ source: DrumSource, cache: AudioBufferCache) -> AVAudioPCMBuffer? {
        if let trim = source.trim {
            return try? TrimRender.read(url: source.url, start: trim.start, end: trim.end, fadeIn: SampleTrim.declick,
                                        fadeOut: trim.effectiveFadeOut, edit: trim.edit, convertTo: cache.format, maxSeconds: maxSeconds)
        }
        guard let whole = try? cache.buffer(for: source.url) else { return nil }
        let limit = AVAudioFrameCount(maxSeconds * whole.format.sampleRate)
        if whole.frameLength <= limit { return whole }
        let shortened = AVAudioPCMBuffer(pcmFormat: whole.format, frameCapacity: limit)
        guard let shortened, let from = whole.floatChannelData, let to = shortened.floatChannelData else { return whole }
        shortened.frameLength = limit
        for c in 0..<Int(whole.format.channelCount) { to[c].update(from: from[c], count: Int(limit)) }
        return shortened
    }
}
