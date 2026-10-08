import AVFoundation
import Foundation

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
    private var urls: [Int64: URL] = [:]
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
    /// `urls` maps each track's sample id to its file; the files are decoded in the background.
    public func update(pattern new: DrumPattern, urls newURLs: [Int64: URL]) {
        lock.lock()
        pattern = new
        urls = newURLs
        lock.unlock()
        for (i, track) in new.tracks.enumerated() where i < nodes.count {
            nodes[i].volume = track.muted ? 0 : track.volume
        }
        for url in newURLs.values where cache.cached(url) == nil {
            decodeQueue.async { [cache] in _ = try? cache.buffer(for: url) }
        }
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
        let pattern = self.pattern, urls = self.urls, bpm = _bpm
        var seq = sequencer ?? DrumSequencer(startTime: Self.nowSeconds())
        lock.unlock()

        let now = Self.nowSeconds()
        let events = seq.advance(now: now, lookahead: Self.lookahead, bpm: bpm, pattern: pattern)
        lock.lock(); sequencer = seq; lock.unlock()

        for event in events {
            let when = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: event.time))
            for index in event.tracks where index < nodes.count {
                guard let url = urls[pattern.tracks[index].sampleID], let buffer = cache.cached(url) else { continue }
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
