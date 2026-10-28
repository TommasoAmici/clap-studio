import Foundation

/// Commands for the persistent helper; samples are read and never written.
public struct VST3LiveCommand: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case play, stop, edit, update, volume, snapshot, closeEditor }
    public var operation: Operation
    public var requestID: UUID?
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
    public var requestID: UUID?
    public var playbackToken: UUID?
    public var sampleID: Int64?
    public var duration: Double = 0
    public var chain: [EffectSlot]?
    public var error: String?
    public init(sampleID: Int64? = nil, duration: Double = 0, chain: [EffectSlot]? = nil, error: String? = nil, requestID: UUID? = nil, playbackToken: UUID? = nil) {
        self.playbackToken = playbackToken
        self.requestID = requestID
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
    private var snapshots: [UUID: CheckedContinuation<[EffectSlot], any Error>] = [:]

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
                self?.failSnapshots(error)
                self?.onStatus?(VST3LiveStatus(error: error.localizedDescription))
            }
        }
        monitor = Task.detached(priority: .utility) { [weak self] in
            var modified: Date?
            let path = directory.appendingPathComponent("status.json")
            while !Task.isCancelled {
                let attributes = try? FileManager.default.attributesOfItem(atPath: path.path)
                if let date = attributes?[.modificationDate] as? Date, date != modified,
                   let size = attributes?[.size] as? NSNumber, size.intValue <= 64 * 1024 * 1024 {
                    modified = date
                    if let data = try? Data(contentsOf: path),
                       let status = try? JSONDecoder().decode(VST3LiveStatus.self, from: data), !Task.isCancelled {
                        await self?.receive(status, from: directory)
                    }
                }
                let replies = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                for reply in replies where reply.lastPathComponent.hasPrefix("reply-") {
                    let attributes = try? FileManager.default.attributesOfItem(atPath: reply.path)
                    guard let size = attributes?[.size] as? NSNumber, size.intValue <= 64 * 1024 * 1024,
                          let data = try? Data(contentsOf: reply),
                          let status = try? JSONDecoder().decode(VST3LiveStatus.self, from: data), !Task.isCancelled else { continue }
                    await self?.receive(status, from: directory)
                    try? FileManager.default.removeItem(at: reply)
                }
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            }
        }
    }

    private func receive(_ status: VST3LiveStatus, from directory: URL) {
        guard folder == directory else { return }
        if let id = status.requestID, let continuation = snapshots.removeValue(forKey: id) {
            if let chain = status.chain { continuation.resume(returning: chain) }
            else { continuation.resume(throwing: VST3Error.message(status.error ?? "The plug-in did not return its settings.")) }
        }
        onStatus?(status)
    }

    public func send(_ command: VST3LiveCommand) throws {
        guard let folder else { throw VST3Error.message("Start the effects chain before previewing.") }
        sequence += 1
        let path = folder.appendingPathComponent(String(format: "command-%08d.json", sequence))
        try JSONEncoder().encode(command).write(to: path, options: .atomic)
    }

    /// Capture hidden preset state at bounce time, including an editor that is still open.
    public func snapshot() async throws -> [EffectSlot] {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            snapshots[id] = continuation
            var command = VST3LiveCommand(operation: .snapshot); command.requestID = id
            do { try send(command) }
            catch { snapshots.removeValue(forKey: id)?.resume(throwing: error) }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.snapshots.removeValue(forKey: id)?.resume(throwing: VST3Error.message("The plug-in did not return its settings."))
            }
        }
    }

    private func failSnapshots(_ error: any Error) {
        let pending = snapshots.values; snapshots.removeAll()
        for continuation in pending { continuation.resume(throwing: error) }
    }

    public var isRunning: Bool { folder != nil }

    public func close() {
        failSnapshots(CancellationError())
        monitor?.cancel(); monitor = nil
        processTask?.cancel(); processTask = nil
        folder = nil
    }
}
