import Darwin
import Foundation

/// Runs untrusted plug-in calls in a disposable process, with a deadline.
enum VST3Process {
    static func run(executable: URL, arguments: [String], timeout: TimeInterval, heartbeat: URL? = nil) async throws {
        let worker = Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable; process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try Task.checkCancellation()
            try process.run()
            defer {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
            let began = Date()
            while process.isRunning {
                try Task.checkCancellation()
                let lastActivity = heartbeat.flatMap {
                    (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                } ?? began
                guard Date().timeIntervalSince(lastActivity) < timeout else {
                    throw VST3Error.message("The plug-in stopped responding and was closed. Original samples are unchanged.")
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            try Task.checkCancellation()
            guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                throw VST3Error.message("The plug-in stopped unexpectedly. You can remove it or try another effect. Original samples are unchanged.")
            }
        }
        try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
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
