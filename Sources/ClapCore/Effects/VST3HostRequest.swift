import Foundation

/// File-based messages keep plug-in output away from the app's process.
public struct VST3HostRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case inspect, parameters, render }
    public var operation: Operation
    public var bundle: URL?
    public var plugin: VST3Plugin?
    public var chain: [EffectSlot]?
    public var source: URL?
    public var destination: URL?
    public var tailSeconds: Double?
    public var heartbeat: URL?

    public init(operation: Operation, bundle: URL? = nil, plugin: VST3Plugin? = nil, chain: [EffectSlot]? = nil,
                source: URL? = nil, destination: URL? = nil, tailSeconds: Double? = nil) {
        self.operation = operation; self.bundle = bundle; self.plugin = plugin; self.chain = chain
        self.source = source; self.destination = destination; self.tailSeconds = tailSeconds
    }

    static func send(_ request: VST3HostRequest, timeout: TimeInterval = 30) async throws -> VST3HostReply {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clap-vst-request-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                              attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("request.json"), output = folder.appendingPathComponent("reply.json")
        var request = request
        if request.operation == .render { request.heartbeat = folder.appendingPathComponent("heartbeat") }
        try JSONEncoder().encode(request).write(to: input, options: .atomic)
        try await VST3Process.run(executable: VST3Process.helperURL(), arguments: [input.path, output.path], timeout: timeout, heartbeat: request.heartbeat)
        let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 64 * 1024 * 1024 else { throw VST3Error.message("The plug-in returned too much data.") }
        let reply = try JSONDecoder().decode(VST3HostReply.self, from: Data(contentsOf: output))
        if let error = reply.error { throw VST3Error.message(error) }
        return reply
    }
}

public struct VST3HostReply: Codable, Sendable {
    public var plugins: [VST3Plugin]?
    public var parameters: [VST3Parameter]?
    public var error: String?
    public init(plugins: [VST3Plugin]? = nil, parameters: [VST3Parameter]? = nil, error: String? = nil) {
        self.plugins = plugins; self.parameters = parameters; self.error = error
    }
}

/// These entry points belong only to the isolated helper executable.
public enum VST3HostWorker {
    @MainActor public static func run(_ request: VST3HostRequest) async throws -> VST3HostReply {
        switch request.operation {
        case .inspect:
            guard let bundle = request.bundle else { throw VST3Error.message("Missing plug-in bundle.") }
            return VST3HostReply(plugins: try VST3Plugin.effectsInProcess(in: bundle))
        case .parameters:
            guard let plugin = request.plugin else { throw VST3Error.message("Missing plug-in class.") }
            return VST3HostReply(parameters: try plugin.parametersInProcess())
        case .render:
            guard let source = request.source, let destination = request.destination, let chain = request.chain else {
                throw VST3Error.message("Missing render recipe.")
            }
            try await EffectBounce.writeInProcess(source: source, trim: nil, chain: chain, to: destination,
                                                 tailSeconds: request.tailSeconds ?? 2, heartbeat: request.heartbeat)
            return VST3HostReply()
        }
    }
}
