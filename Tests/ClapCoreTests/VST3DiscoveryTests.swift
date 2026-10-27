import Foundation
import Testing
@testable import ClapCore

@Suite struct VST3DiscoveryTests {
    @Test func findsBundlesInsideVendorFoldersWithoutDescendingIntoBundles() throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Vendor/Echo.vst3", "Gain.vst3", "Gain.vst3/Contents/Hidden.vst3", "Old.vst"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let bundles = VST3Discovery.bundles(in: [root, root])
        #expect(bundles.map(\.lastPathComponent) == ["Echo.vst3", "Gain.vst3"], "VST3 bundles are unique and nested bundles are not scanned")
    }
    @Test func missingLocationsAreIgnored() {
        #expect(VST3Discovery.bundles(in: [URL(fileURLWithPath: "/missing-vst3-location")]).isEmpty)
    }
}
