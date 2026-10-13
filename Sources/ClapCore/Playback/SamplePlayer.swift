import AVFoundation
import Foundation

public struct PlaybackState: Sendable, Equatable {
    public var sampleID: Int64?
    /// Where in the file (seconds) the current playback started.
    public var startSeconds: Double = 0
    public var startedAt: Date?
    public var duration: Double = 0
    /// Playback speed (1 = as recorded); the playhead moves through the file at this rate.
    public var rate: Double = 1
    /// False when what plays no longer runs along the file (a reversed or sped-up edit), so there is no playhead to draw.
    public var tracksPlayhead = true

    public init(sampleID: Int64? = nil, startSeconds: Double = 0, startedAt: Date? = nil, duration: Double = 0, rate: Double = 1,
                tracksPlayhead: Bool = true) {
        self.sampleID = sampleID; self.startSeconds = startSeconds
        self.startedAt = startedAt; self.duration = duration; self.rate = rate; self.tracksPlayhead = tracksPlayhead
    }

    /// Current playhead in seconds, or nil when stopped.
    public func playhead(at date: Date = Date()) -> Double? {
        guard sampleID != nil, tracksPlayhead, let startedAt else { return nil }
        let t = startSeconds + date.timeIntervalSince(startedAt) * rate
        return t <= duration ? t : nil
    }
}

/// Low-latency preview player: a pool of player nodes lets a new sound start
/// immediately while the previous one fades out (no clicks when hovering fast).
public final class SamplePlayer: @unchecked Sendable {
    private final class Voice {
        let node = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        let gain = AVAudioUnitEQ(numberOfBands: 0)
        var busy = false
        var token = 0
    }

    public let cache: AudioBufferCache
    public var onStateChange: (@Sendable (PlaybackState) -> Void)?

    private let engine = AVAudioEngine()
    private var voices: [Voice] = []
    private let decodeQueue = DispatchQueue(label: "clap.decode", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var requestToken = 0
    private var _state = PlaybackState()
    private var configObserver: NSObjectProtocol?

    public var state: PlaybackState { lock.lock(); defer { lock.unlock() }; return _state }

    public var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0, min(1, newValue)) }
    }

    public init(voiceCount: Int = 4) {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        cache = AudioBufferCache(sampleRate: rate > 0 ? rate : 44_100)
        for _ in 0..<voiceCount {
            let voice = Voice()
            engine.attach(voice.node)
            engine.attach(voice.timePitch)
            voice.timePitch.bypass = true
            engine.attach(voice.gain)
            voice.gain.bypass = true
            engine.connect(voice.node, to: voice.timePitch, format: cache.format)
            engine.connect(voice.timePitch, to: voice.gain, format: cache.format)
            engine.connect(voice.gain, to: engine.mainMixerNode, format: cache.format)
            voices.append(voice)
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restartEngine()
        }
    }

    deinit { if let o = configObserver { NotificationCenter.default.removeObserver(o) } }

    private func restartEngine() {
        engine.stop()
        try? engine.start()
    }

    private func ensureRunning() throws {
        if !engine.isRunning { engine.prepare(); try engine.start() }
    }

    // MARK: playback

    /// Plays `url` from `startSeconds`. Decoding happens off the main thread on a cache miss;
    /// a later request supersedes an earlier one that is still decoding.
    /// `rate` stretches time and `pitchCents` transposes, each without changing the other
    /// (used to fit a loop to the project's tempo and key). The defaults play the file untouched.
    public func play(sampleID: Int64, url: URL, startSeconds: Double = 0, rate: Float = 1, pitchCents: Float = 0, gainDB: Float = 0,
                     completion: (@Sendable (Error?) -> Void)? = nil) {
        lock.lock(); requestToken += 1; let token = requestToken; lock.unlock()

        if let buffer = cache.cached(url) {
            start(buffer, sampleID: sampleID, startSeconds: startSeconds, rate: rate, pitchCents: pitchCents, gainDB: gainDB, token: token, completion: completion)
            return
        }
        decodeQueue.async { [weak self] in
            guard let self else { return }
            do {
                let buffer = try self.cache.buffer(for: url)
                self.lock.lock(); let current = self.requestToken; self.lock.unlock()
                guard current == token else { completion?(nil); return }
                DispatchQueue.main.async {
                    self.start(buffer, sampleID: sampleID, startSeconds: startSeconds, rate: rate, pitchCents: pitchCents, gainDB: gainDB, token: token, completion: completion)
                }
            } catch { completion?(error) }
        }
    }

    /// Plays part of a file read straight from disk (so the region can be anywhere in a very long file),
    /// with a click-free start and a fade at the end. The playhead reports positions in the file.
    public func playRegion(sampleID: Int64, url: URL, start: Double, end: Double?, fadeOut: Double = SampleTrim.declick,
                           edit: SampleEdit? = nil, rate: Float = 1, pitchCents: Float = 0, gainDB: Float = 0,
                           completion: (@Sendable (Error?) -> Void)? = nil) {
        lock.lock(); requestToken += 1; let token = requestToken; lock.unlock()
        decodeQueue.async { [weak self] in
            guard let self else { return }
            do {
                let buffer = try TrimRender.read(url: url, start: start, end: end, fadeIn: SampleTrim.declick, fadeOut: fadeOut,
                                                 edit: edit, convertTo: self.cache.format, maxSeconds: 300)
                self.lock.lock(); let current = self.requestToken; self.lock.unlock()
                guard current == token else { completion?(nil); return }
                DispatchQueue.main.async {
                    self.start(buffer, sampleID: sampleID, startSeconds: 0, origin: start, rate: rate, pitchCents: pitchCents,
                               gainDB: gainDB, tracksPlayhead: !(edit?.changesTiming ?? false), token: token, completion: completion)
                }
            } catch { completion?(error) }
        }
    }

    public func prefetch(_ urls: [URL]) {
        for url in urls where cache.cached(url) == nil {
            decodeQueue.async { [cache] in _ = try? cache.buffer(for: url) }
        }
    }

    public func stop(fade: Bool = true) {
        lock.lock(); requestToken += 1; lock.unlock()
        for v in voices where v.busy == false && v.node.isPlaying { fadeOut(v, fade: fade) }
        for v in voices where v.node.isPlaying { fadeOut(v, fade: fade) }
        setState(PlaybackState())
    }

    private func start(_ buffer: AVAudioPCMBuffer, sampleID: Int64, startSeconds: Double, origin: Double = 0, rate playbackRate: Float,
                       pitchCents: Float, gainDB: Float, tracksPlayhead: Bool = true, token: Int,
                       completion: (@Sendable (Error?) -> Void)?) {
        lock.lock(); let current = requestToken; lock.unlock()
        guard current == token else { completion?(nil); return }
        do {
            try ensureRunning()
            let rate = buffer.format.sampleRate
            let startFrame = max(0, min(Int(startSeconds * rate), Int(buffer.frameLength) - 1))
            guard let slice = Self.slice(buffer, from: startFrame) else { completion?(nil); return }

            for v in voices where v.node.isPlaying { fadeOut(v, fade: true) }
            let voice = voices.first { !$0.busy && !$0.node.isPlaying } ?? voices[0]
            voice.token += 1
            let voiceToken = voice.token
            voice.node.volume = 1
            let neutral = playbackRate == 1 && pitchCents == 0
            voice.timePitch.bypass = neutral
            voice.timePitch.rate = playbackRate
            voice.timePitch.pitch = pitchCents
            voice.gain.bypass = gainDB == 0
            voice.gain.globalGain = gainDB
            voice.node.scheduleBuffer(slice, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async { self?.finished(voice: voice, voiceToken: voiceToken, sampleID: sampleID) }
            }
            voice.node.play()
            setState(PlaybackState(sampleID: sampleID, startSeconds: origin + Double(startFrame) / rate,
                                   startedAt: Date(), duration: origin + Double(buffer.frameLength) / rate,
                                   rate: Double(playbackRate), tracksPlayhead: tracksPlayhead))
            completion?(nil)
        } catch { completion?(error) }
    }

    private func finished(voice: Voice, voiceToken: Int, sampleID: Int64) {
        guard voice.token == voiceToken, state.sampleID == sampleID else { return }
        setState(PlaybackState())
    }

    private func fadeOut(_ voice: Voice, fade: Bool) {
        voice.token += 1
        guard fade else { voice.node.stop(); voice.node.volume = 1; return }
        voice.busy = true
        let steps = 4
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(3 * i)) {
                voice.node.volume = max(0, 1 - Float(i) / Float(steps))
                if i == steps { voice.node.stop(); voice.node.volume = 1; voice.busy = false }
            }
        }
    }

    private func setState(_ new: PlaybackState) {
        lock.lock(); _state = new; lock.unlock()
        onStateChange?(new)
    }

    static func slice(_ buffer: AVAudioPCMBuffer, from start: Int) -> AVAudioPCMBuffer? {
        if start == 0 { return buffer }
        let remaining = Int(buffer.frameLength) - start
        guard remaining > 0,
              let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(remaining)),
              let src = buffer.floatChannelData, let dst = out.floatChannelData else { return nil }
        for c in 0..<Int(buffer.format.channelCount) {
            dst[c].update(from: src[c] + start, count: remaining)
        }
        out.frameLength = AVAudioFrameCount(remaining)
        return out
    }
}
