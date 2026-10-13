import AVFoundation
import Foundation

/// A sample on a drum track: its file and the part of it to play.
public struct DrumSource: Equatable, Sendable {
    public var url: URL
    public var trim: SampleTrim?
    public init(url: URL, trim: SampleTrim? = nil) { self.url = url; self.trim = trim }
}

/// Plays a `DrumPattern` in a loop on its own audio engine. Steps are scheduled a short time ahead against the
/// host clock, so timing is set by the audio hardware rather than by when a timer happens to fire.
public final class DrumMachine: @unchecked Sendable {
    public static let lookahead = 0.12
    private static let tickInterval = 0.025

    /// Called on the main queue as each step begins (for a moving playhead).
    public var onStep: (@Sendable (Int) -> Void)?
    /// Called on the main queue when playback starts or stops.
    public var onRunningChange: (@Sendable (Bool) -> Void)?

    private let cache: AudioBufferCache
    private let engine = AVAudioEngine()
    private let nodes: [AVAudioPlayerNode]
    private let queue = DispatchQueue(label: "clap.drums", qos: .userInteractive)
    private let decodeQueue = DispatchQueue(label: "clap.drums.decode", qos: .userInitiated, attributes: .concurrent)
    private var timer: DispatchSourceTimer?

    private let lock = NSLock()
    private var pattern = DrumPattern()
    private var sources: [Int64: DrumSource] = [:]
    private var ready: [Int64: ReadySound] = [:]        // decoded (and trimmed) audio, by sample id
    private struct ReadySound { let source: DrumSource; let buffer: AVAudioPCMBuffer }
    private var _bpm = DrumTiming.defaultBPM
    private var sequencer: DrumSequencer?

    public private(set) var isRunning = false

    public init(cache: AudioBufferCache) {
        self.cache = cache
        var made: [AVAudioPlayerNode] = []
        for _ in 0..<DrumPattern.maxTracks {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: cache.format)
            made.append(node)
        }
        nodes = made
    }

    deinit { stop() }

    public var bpm: Double {
        get { lock.lock(); defer { lock.unlock() }; return _bpm }
        set { lock.lock(); _bpm = min(300, max(30, newValue)); lock.unlock() }
    }

    /// Replaces the pattern (takes effect from the next step, so it can be edited while playing).
    /// `sources` says where each track's sample is and how it is trimmed; the audio is prepared in the background.
    public func update(pattern new: DrumPattern, sources newSources: [Int64: DrumSource]) {
        lock.lock()
        pattern = new
        sources = newSources
        let missing = newSources.filter { ready[$0.key]?.source != $0.value }
        ready = ready.filter { newSources[$0.key] == $0.value.source }
        lock.unlock()
        for (i, track) in new.tracks.enumerated() where i < nodes.count {
            nodes[i].volume = track.muted ? 0 : track.volume
        }
        for (id, source) in missing {
            decodeQueue.async { [weak self] in self?.prepare(id: id, source: source) }
        }
    }

    private func prepare(id: Int64, source: DrumSource) {
        let buffer: AVAudioPCMBuffer?
        if let trim = source.trim {
            buffer = try? TrimRender.read(url: source.url, start: trim.start, end: trim.end, fadeIn: SampleTrim.declick,
                                          fadeOut: trim.effectiveFadeOut, edit: trim.edit, convertTo: cache.format, maxSeconds: 60)
        } else {
            buffer = try? cache.buffer(for: source.url)
        }
        guard let buffer else { return }
        lock.lock()
        if sources[id] == source { ready[id] = ReadySound(source: source, buffer: buffer) }
        lock.unlock()
    }

    public func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            do {
                if !engine.isRunning { engine.prepare(); try engine.start() }
            } catch { return }
            for node in nodes { node.play() }
            lock.lock(); sequencer = DrumSequencer(startTime: Self.nowSeconds() + 0.06); lock.unlock()
            isRunning = true
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: Self.tickInterval, leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
            DispatchQueue.main.async { [onRunningChange] in onRunningChange?(true) }
        }
    }

    public func stop() {
        queue.async { [self] in
            guard isRunning else { return }
            timer?.cancel(); timer = nil
            for node in nodes { node.stop() }          // drops anything scheduled but not yet played
            isRunning = false
            DispatchQueue.main.async { [onRunningChange] in onRunningChange?(false) }
        }
    }

    private func tick() {
        lock.lock()
        let pattern = self.pattern, ready = self.ready, bpm = _bpm
        var seq = sequencer ?? DrumSequencer(startTime: Self.nowSeconds())
        lock.unlock()

        let now = Self.nowSeconds()
        let events = seq.advance(now: now, lookahead: Self.lookahead, bpm: bpm, pattern: pattern)
        lock.lock(); sequencer = seq; lock.unlock()

        for event in events {
            let when = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: event.time))
            for index in event.tracks where index < nodes.count {
                guard let buffer = ready[pattern.tracks[index].sampleID]?.buffer else { continue }
                // .interrupts cuts the previous hit on this track, like a drum machine voice.
                nodes[index].scheduleBuffer(buffer, at: when, options: .interrupts, completionHandler: nil)
            }
            let delay = max(0, event.time - now)
            let step = event.step
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.onStep?(step) }
        }
    }

    private static func nowSeconds() -> Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }
}
