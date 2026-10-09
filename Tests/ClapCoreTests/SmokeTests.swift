import Testing
@testable import ClapCore

@Test func versionIsSet() { #expect(ClapCoreInfo.version == "0.7") }
