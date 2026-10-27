import Darwin
import Foundation

/// Runs untrusted plug-in calls in a disposable process, with a deadline.
enum VST3Process {
    static func run(executable: URL, arguments: [String], timeout: TimeInterval, heartbeat: URL? = nil, startupTimeout: TimeInterval? = nil) async throws {
        let cancellation = VST3Cancellation()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try supervise(executable: executable, arguments: arguments, timeout: timeout,
                                      heartbeat: heartbeat, startupTimeout: startupTimeout, cancellation: cancellation)
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }

    // Foundation Process must be launched and waited on the same thread's run loop.
    private static func supervise(executable: URL, arguments: [String], timeout: TimeInterval,
                                  heartbeat: URL?, startupTimeout: TimeInterval?, cancellation: VST3Cancellation) throws {
        let process = Process()
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try cancellation.check()
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        var lastActivity = ContinuousClock.now
        var lastHeartbeat: Date?
        while process.isRunning {
            try cancellation.check()
            // Read fresh filesystem attributes rather than URL's cached resource values.
            if let heartbeat, let modified = (try? FileManager.default.attributesOfItem(atPath: heartbeat.path)[.modificationDate]) as? Date,
               modified != lastHeartbeat {
                lastHeartbeat = modified; lastActivity = .now
            }
            let deadline = heartbeat != nil && lastHeartbeat == nil ? (startupTimeout ?? timeout) : timeout
            guard lastActivity.duration(to: .now) < .seconds(deadline) else {
                throw VST3Error.message("The plug-in stopped responding and was closed. Original samples are unchanged.")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        try cancellation.check()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw VST3Error.message("The plug-in stopped unexpectedly. You can remove it or try another effect. Original samples are unchanged.")
        }
    }

    static func helperURL() throws -> URL {
        let executable = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).standardizedFileURL
        let origins = [executable.deletingLastPathComponent(), Bundle(for: VST3HostBundle.self).bundleURL]
        for origin in origins {
            var directory = origin
            for _ in 0..<5 {
                let candidate = directory.appendingPathComponent("ClapVSTHost")
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
                directory.deleteLastPathComponent()
            }
        }
        throw VST3Error.message("The plug-in helper is missing. Reinstall Clap Studio to use VST3 effects.")
    }
}

private final class VST3HostBundle: NSObject {}

private final class VST3Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
    }
}
