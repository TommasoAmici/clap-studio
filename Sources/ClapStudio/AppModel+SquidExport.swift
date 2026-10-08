import ClapCore
import Foundation

/// Sending samples to a stick.
extension AppModel {
    /// Opens the export sheet. `ids` fill the bank (or the Pool); the drive and place come from where the user is looking.
    func openSquidExport(ids: [Int64], drive: String? = nil, set: String? = nil, pool: Bool = false) {
        guard squidEnabled else { return }
        squidItems = ids
        squidTarget = SquidTarget(drive: drive ?? usbSelection?.drive ?? usbDrives.first?.id, set: set, pool: pool)
        showSquidExport = true
    }
}
