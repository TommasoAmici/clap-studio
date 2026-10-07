import Foundation
@testable import ClapCore

enum TestSupport {
    static func tempDir(_ name: String = UUID().uuidString) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clap-\(name)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeStore() throws -> (LibraryStore, URL) {
        let dir = tempDir()
        return (try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path), dir)
    }

    @discardableResult
    static func write(_ bytes: [UInt8], to url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data(bytes))
        return url
    }
}
