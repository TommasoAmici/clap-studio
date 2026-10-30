import AppKit
import ClapCore
import Observation

/// The current join dialog and cancellable export, kept apart from library edits.
@MainActor @Observable
final class JoinState {
    var show = false
    var sources: [JoinSource] = []
    var running = false
    /// What the new files are called (`<name> 01.wav`); starts as "Joined" each time the sheet opens.
    var name = JoinNaming.defaultName
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var pendingSettings: JoinSettings?
    @ObservationIgnored var folderPanel: NSOpenPanel?
}
