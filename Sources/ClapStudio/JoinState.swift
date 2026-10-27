import AppKit
import ClapCore
import Observation

/// The current join dialog and cancellable export, kept apart from library edits.
@MainActor @Observable
final class JoinState {
    var show = false
    var sources: [JoinSource] = []
    var running = false
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var pendingSettings: JoinSettings?
    @ObservationIgnored var folderPanel: NSOpenPanel?
}
