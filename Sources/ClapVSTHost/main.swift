import AppKit
import ClapCore
import Darwin
import Foundation

@main enum ClapVSTHost {
    static func main() {
        guard CommandLine.arguments.count == 3 else { exit(2) }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let parent = getppid()
        // The watcher still runs when third-party code blocks the helper's main thread.
        let watcher = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        watcher.schedule(deadline: .now(), repeating: 1)
        watcher.setEventHandler { if getppid() != parent { _exit(0) } }
        watcher.resume()
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        DispatchQueue.main.async {
            Task { @MainActor in
                let reply: VST3HostReply
                do {
                    let request = try JSONDecoder().decode(VST3HostRequest.self, from: Data(contentsOf: input))
                    reply = try await VST3HostWorker.run(request)
                } catch { reply = VST3HostReply(error: error.localizedDescription) }
                do { try JSONEncoder().encode(reply).write(to: output, options: .atomic) }
                catch { exit(3) }
                // Exit rather than running plug-in global destructors after the reply.
                _exit(0)
            }
        }
        application.run()
        withExtendedLifetime(watcher) {}
    }
}
