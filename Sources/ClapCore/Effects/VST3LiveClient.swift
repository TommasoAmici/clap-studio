import Foundation

/// Commands for the persistent helper; samples are read and never written.
public struct VST3LiveCommand: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case play, stop, edit, update, volume }
    public var operation: Operation
    public var source: URL?
    public var trim: SampleTrim?
    public var sampleID: Int64?
    public var effectID: UUID?
    public var chain: [EffectSlot]?
    public var rate: Float = 1
    public var pitchCents: Float = 0
    public var gainDB: Float = 0
    public var volume: Float = 1
    public var tailSeconds: Double = 2
    public init(operation: Operation) { self.operation = operation }
}

public struct VST3LiveStatus: Codable, Sendable {
    public var revision = UUID()
    public var sampleID: Int64?
    public var duration: Double = 0
    public var chain: [EffectSlot]?
    public var error: String?
    public init(sampleID: Int64? = nil, duration: Double = 0, chain: [EffectSlot]? = nil, error: String? = nil) {
        self.sampleID = sampleID; self.duration = duration; self.chain = chain; self.error = error
    }
}

/// Keeps a supervised helper warm so changing a sample does not reload every effect.
@MainActor public final class VST3LiveClient {
    public var onStatus: ((VST3LiveStatus) -> Void)?
    private var folder: URL?
    private var processTask: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var sequence = 0

    public init() {}

    public func start(chain: [EffectSlot]) throws {
        close()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clap-vst-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                              attributes: [.posixPermissions: 0o700])
        folder = directory; sequence = 0
        var request = VST3HostRequest(operation: .live, chain: chain)
        request.sessionDirectory = directory
        processTask = Task { [weak self] in
            defer { try? FileManager.default.removeItem(at: directory) }
            do { _ = try await VST3HostRequest.send(request, timeout: 30) }
            catch {
                guard !Task.isCancelled, self?.folder == directory else { return }
                self?.monitor?.cancel(); self?.folder = nil
                self?.onStatus?(VST3LiveStatus(error: error.localizedDescription))
            }
        }
        monitor = Task { [weak self] in
            var revision: UUID?
            let path = directory.appendingPathComponent("status.json")
            while !Task.isCancelled {
                if let data = try? Data(contentsOf: path), data.count <= 64 * 1024 * 1024,
                   let status = try? JSONDecoder().decode(VST3LiveStatus.self, from: data), status.revision != revision {
                    revision = status.revision; self?.onStatus?(status)
                }
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            }
        }
    }

    public func send(_ command: VST3LiveCommand) throws {
        guard let folder else { throw VST3Error.message("Start the effects chain before previewing.") }
        sequence += 1
        let path = folder.appendingPathComponent(String(format: "command-%08d.json", sequence))
        try JSONEncoder().encode(command).write(to: path, options: .atomic)
    }

    public var isRunning: Bool { folder != nil }

    public func close() {
        monitor?.cancel(); monitor = nil
        processTask?.cancel(); processTask = nil
        folder = nil
    }
}
