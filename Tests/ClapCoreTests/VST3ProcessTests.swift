import Darwin
import Foundation
import Testing
@testable import ClapCore

@Suite(.serialized) struct VST3ProcessTests {
    @Test func cancellingBeforeDispatchNeverStartsTheHelper() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("started")
        let task = Task {
            try? await Task.sleep(for: .milliseconds(50))
            try await VST3Process.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                    arguments: ["-c", "touch \"$1\"", "fixture", marker.path], timeout: 2)
        }
        task.cancel()
        do { try await task.value; Issue.record("A pre-cancelled request must throw") }
        catch { #expect(error is CancellationError) }
        #expect(!FileManager.default.fileExists(atPath: marker.path), "Cancel prevents the helper from starting")
    }

    @Test func repeatedHelpersAreReapedAfterSuspendedCalls() async throws {
        for _ in 0..<25 {
            try await VST3Process.run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], timeout: 2)
            await Task.yield()
        }
    }

    @Test func startupAndResponsiveHeartbeatHaveSeparateDeadlines() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let heartbeat = folder.appendingPathComponent("heartbeat")
        try await VST3Process.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                arguments: ["-c", "sleep 0.4; i=0; while [ $i -lt 8 ]; do touch \"$1\"; sleep 0.1; i=$((i+1)); done", "fixture", heartbeat.path],
                                timeout: 0.3, heartbeat: heartbeat, startupTimeout: 2)
        #expect(FileManager.default.fileExists(atPath: heartbeat.path), "A cold start can take longer than the inactivity window, then each new heartbeat extends it")
    }

    @Test func aStoppedHeartbeatStillTimesOut() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let heartbeat = folder.appendingPathComponent("heartbeat")
        do {
            try await VST3Process.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                    arguments: ["-c", "touch \"$1\"; exec /bin/sleep 10", "fixture", heartbeat.path],
                                    timeout: 0.2, heartbeat: heartbeat, startupTimeout: 2)
            Issue.record("A helper with no new heartbeat must time out")
        } catch { #expect(error.localizedDescription.contains("responding")) }
    }

    @Test func aCrashingHelperReportsFailureWithoutClosingTheApp() async throws {
        do {
            try await VST3Process.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "kill -KILL $$"], timeout: 2)
            Issue.record("A crashing helper must report failure")
        } catch {
            #expect(error.localizedDescription.contains("stopped"), "A plugin crash becomes a readable error")
        }
    }

    @Test func aHungHelperIsKilledAndReaped() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pidFile = folder.appendingPathComponent("pid")
        do {
            try await VST3Process.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                    arguments: ["-c", "echo $$ > \"$1\"; trap '' TERM; exec /bin/sleep 3600", "fixture", pidFile.path], timeout: 0.2)
            Issue.record("A hung helper must time out")
        } catch {
            #expect(error.localizedDescription.contains("responding"), "A timed out plugin explains what happened")
        }
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == -1 && errno == ESRCH, "The hung helper is gone, including its ignored TERM handler")
    }

    @Test func cancellingAHelperStopsItBeforeItsDeadline() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pidFile = folder.appendingPathComponent("pid")
        let task = Task {
            try await VST3Process.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                    arguments: ["-c", "echo $$ > \"$1\"; exec /bin/sleep 3600", "fixture", pidFile.path], timeout: 3600)
        }
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                // Cancel from a worker when the child is ready, independent of the
                // Swift test executor being busy with hundreds of DSP cases.
                for _ in 0..<12000 {
                    if FileManager.default.fileExists(atPath: pidFile.path) { break }
                    Thread.sleep(forTimeInterval: 0.01)
                }
                task.cancel(); ready.resume()
            }
        }
        do { try await task.value; Issue.record("A cancelled request must throw") }
        catch { #expect(error is CancellationError) }
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == -1 && errno == ESRCH, "Cancel kills and reaps the helper rather than abandoning it")
    }
    @Test func crashingBundleEntryIsContainedByTheRealHelper() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try faultyBundle(in: folder, entry: "kill(getpid(), SIGKILL); return true;")
        do {
            _ = try await VST3Plugin.effects(in: bundle)
            Issue.record("A crashing bundle must fail to load")
        } catch {
            #expect(error.localizedDescription.contains("stopped unexpectedly"), "A real plug-in crash closes only its helper")
        }
    }

    @MainActor @Test func hangingBundleEntryLeavesTheMainActorAvailable() async throws {
        let folder = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try faultyBundle(in: folder, entry: "signal(SIGTERM, SIG_IGN); for (;;) pause(); return true;")
        let load = Task { try await VST3HostRequest.send(VST3HostRequest(operation: .inspect, bundle: bundle), timeout: 1) }
        try await Task.sleep(for: .milliseconds(100))
        let check = ContinuousClock.now
        do { _ = try await load.value; Issue.record("A stuck bundle must time out") }
        catch { #expect(error.localizedDescription.contains("responding")) }
        #expect(check.duration(to: .now) < .seconds(2), "The main actor resumes while bundleEntry is still stuck in its helper")
    }

    private func faultyBundle(in folder: URL, entry: String) throws -> URL {
        let bundle = folder.appendingPathComponent("Fault.vst3"), contents = bundle.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/Fault")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("fault.c")
        try "#include <stdbool.h>\n#include <signal.h>\n#include <unistd.h>\nbool bundleEntry(void *bundle) { \(entry) }\n".write(to: source, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = ["-dynamiclib", "-mmacosx-version-min=14.0", source.path, "-o", executable.path]
        compiler.standardOutput = FileHandle.nullDevice; compiler.standardError = FileHandle.nullDevice
        try compiler.run(); compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0, "Build the tiny plug-in fault fixture with the installed C compiler")
        let plist: [String: Any] = ["CFBundleExecutable": "Fault", "CFBundleIdentifier": "app.clapstudio.Fault", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }

}
