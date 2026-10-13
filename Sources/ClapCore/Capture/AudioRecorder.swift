import AVFoundation
import Foundation

public enum RecordingError: Error, Equatable, CustomStringConvertible {
    case denied
    case needsAppBundle
    case noInput
    case tooShort
    case silent

    public var description: String {
        switch self {
        case .denied: return "Clap Studio is not allowed to use the microphone. Allow it in System Settings, Privacy & Security, Microphone."
        case .needsAppBundle: return "Recording needs the app bundle (scripts/bundle.sh); a bare build has no microphone permission text."
        case .noInput: return "No audio input is available."
        case .tooShort: return "That was too short to search with. Hold the recording for at least half a second."
        case .silent: return "Nothing was heard. Check the input in System Settings, Sound."
        }
    }
}

/// What a recording has captured so far, measured as the audio arrives.
public struct RecordingStats: Equatable, Sendable {
    public var frames: Int64 = 0
    public var sampleRate: Double = 44100
    public var peak: Float = 0

    public init(sampleRate: Double = 44100) { self.sampleRate = sampleRate }

    public var seconds: Double { sampleRate > 0 ? Double(frames) / sampleRate : 0 }
    public var peakDB: Float { peak > 0 ? 20 * log10(peak) : -120 }

    public static let minimumSeconds = 0.5
    /// Quieter than this is the noise floor of an unplugged or muted input, not a sound.
    public static let silenceFloorDB: Float = -70

    /// Whether the recording can be searched with, or why not.
    public var problem: RecordingError? {
        if seconds < Self.minimumSeconds { return .tooShort }
        if peakDB < Self.silenceFloorDB { return .silent }
        return nil
    }

    /// Counts a block of audio: its length in frames and the loudest sample in it.
    public mutating func add(frames count: Int, peak blockPeak: Float) {
        frames += Int64(count)
        peak = max(peak, blockPeak)
    }

    /// The loudest sample across all channels of a block.
    public static func peak(of channels: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, frames: Int) -> Float {
        var loudest: Float = 0
        for channel in 0..<channelCount {
            for i in 0..<frames { loudest = max(loudest, abs(channels[channel][i])) }
        }
        return loudest
    }
}

/// Records the default microphone to a temporary WAV file, for searching the library with a sound made on the spot.
public final class AudioRecorder: @unchecked Sendable {
    /// Sounds longer than the embedding window (10 s) add nothing, so the recording ends there by itself.
    public static let maxSeconds = 10.0

    /// Called on the main queue about 20 times a second while recording: how loud it is (0...1) and for how long.
    public var onProgress: (@Sendable (_ level: Float, _ seconds: Double) -> Void)?
    /// Called on the main queue when the maximum length is reached, with the finished recording.
    public var onAutoStop: (@Sendable (Result<URL, Error>) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var url: URL?
    private var stats = RecordingStats()
    private var recentPeak: Float = 0
    private var lastReport = Date.distantPast
    private var running = false

    public init() {}

    public var isRecording: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// Asks for microphone access the first time. A bare executable has no usage description, and asking would end the process.
    public static func requestAccess() async throws {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else { throw RecordingError.needsAppBundle }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
            throw RecordingError.denied
        default: throw RecordingError.denied
        }
    }

    public func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw RecordingError.noInput }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clap-recording-\(UUID().uuidString).wav")
        file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        self.url = url
        stats = RecordingStats(sampleRate: format.sampleRate)
        recentPeak = 0
        lastReport = .distantPast
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in self?.handle(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            file = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        running = true
    }

    /// Ends the recording and returns the file, or says why it cannot be used.
    @discardableResult
    public func stop() throws -> URL {
        lock.lock()
        guard running, let url else { lock.unlock(); throw RecordingError.tooShort }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil                      // closes the file
        let finished = stats
        self.url = nil
        lock.unlock()
        if let problem = finished.problem {
            try? FileManager.default.removeItem(at: url)
            throw problem
        }
        return url
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard running, let file else { lock.unlock(); return }
        try? file.write(from: buffer)
        if let data = buffer.floatChannelData {
            let block = RecordingStats.peak(of: data, channelCount: Int(buffer.format.channelCount), frames: Int(buffer.frameLength))
            stats.add(frames: Int(buffer.frameLength), peak: block)
            recentPeak = max(recentPeak, block)
        }
        let seconds = stats.seconds
        let now = Date()
        var report: (Float, Double)?
        if now.timeIntervalSince(lastReport) >= 0.05 {
            lastReport = now
            report = (recentPeak, seconds)
            recentPeak = 0
        }
        let finishedByLength = seconds >= Self.maxSeconds
        lock.unlock()
        if let report { DispatchQueue.main.async { [onProgress] in onProgress?(report.0, report.1) } }
        if finishedByLength {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRecording else { return }
                let result = Result { try self.stop() }
                self.onAutoStop?(result)
            }
        }
    }
}
