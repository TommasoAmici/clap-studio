import ClapCore
import Foundation
import Testing

@Suite struct UsbDriveIdentityTests {
    @Test func sameNamedDrivesKeepSeparateDestinations() {
        let first = UsbDrive(url: URL(fileURLWithPath: "/Volumes/SQUID"), name: "SQUID",
                             formatDescription: "MS-DOS (FAT32)", capacity: nil, available: nil)
        let second = UsbDrive(url: URL(fileURLWithPath: "/Volumes/SQUID 1"), name: "SQUID",
                              formatDescription: "ExFAT", capacity: nil, available: nil)
        #expect(first.id != second.id, "Same-named sticks must remain separate export destinations.")
        #expect(first.isFAT32 && !second.isFAT32, "The destination keeps its own format warning.")
    }
}
