import Foundation

/// Stages and verifies an update beside its destination, keeping the old app until replacement succeeds.
public enum ReleaseInstaller {
    public static let bundleIdentifier = "app.clapstudio.ClapStudio"

    public static func applicationsDirectory() -> URL {
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: system.path) { return system }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    }

    public static func install(archive: URL, version: ReleaseVersion, applications: URL) throws -> URL {
        try ReleaseArchive.validate(archive)
        let fm = FileManager.default
        try fm.createDirectory(at: applications, withIntermediateDirectories: true)
        let stage = applications.appendingPathComponent(".clap-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, stage.path], failure: .invalidArchive)
        try Task.checkCancellation()
        let app = stage.appendingPathComponent("ClapStudio.app", isDirectory: true)
        try validateBundle(app, version: version)
        let destination = applications.appendingPathComponent("ClapStudio.app", isDirectory: true)
        let backupName = ".ClapStudio-backup-\(UUID().uuidString).app"
        let backup = applications.appendingPathComponent(backupName, isDirectory: true)
        let existing = fm.fileExists(atPath: destination.path)
        if existing {
            guard try identity(destination)["CFBundleIdentifier"] as? String == bundleIdentifier else {
                throw ReleaseInstallError.installFailed
            }
        }
        try Task.checkCancellation()
        do {
            if existing {
                _ = try fm.replaceItemAt(destination, withItemAt: app, backupItemName: backupName,
                    options: [.usingNewMetadataOnly, .withoutDeletingBackupItem])
            } else {
                try fm.moveItem(at: app, to: destination)
            }
            try validateBundle(destination, version: version)
            // Clear download quarantine only after verification, while rollback is still available.
            try clearDownloadQuarantine(destination)
        } catch {
            if fm.fileExists(atPath: backup.path) {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: backup, to: destination)
            } else if !existing {
                try? fm.removeItem(at: destination)
            }
            throw ReleaseInstallError.installFailed
        }
        try? fm.removeItem(at: backup)
        return destination
    }

    static func clearDownloadQuarantine(_ app: URL) throws {
        try run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path], failure: .installFailed)
    }

    public static func validateBundle(_ app: URL, version: ReleaseVersion) throws {
        let values = try identity(app)
        guard values["CFBundleIdentifier"] as? String == bundleIdentifier,
              values["CFBundleExecutable"] as? String == "ClapStudio",
              values["CFBundlePackageType"] as? String == "APPL",
              ReleaseVersion(version: values["CFBundleShortVersionString"] as? String,
                             build: values["CFBundleVersion"] as? String) == version else {
            throw ReleaseInstallError.invalidBundle
        }
        let executable = app.appendingPathComponent("Contents/MacOS/ClapStudio")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw ReleaseInstallError.invalidBundle }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], failure: .invalidBundle)
    }

    private static func identity(_ app: URL) throws -> [String: Any] {
        let fm = FileManager.default
        var enumerationFailed = false
        guard (try app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).isDirectory == true,
              (try app.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
              let enumerator = fm.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey],
                  errorHandler: { _, _ in enumerationFailed = true; return false }) else {
            throw ReleaseInstallError.invalidBundle
        }
        for case let item as URL in enumerator {
            guard (try item.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else {
                throw ReleaseInstallError.invalidBundle
            }
        }
        guard !enumerationFailed else { throw ReleaseInstallError.invalidBundle }
        let plist = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let values = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] else {
            throw ReleaseInstallError.invalidBundle
        }
        return values
    }

    static func run(_ executable: String, _ arguments: [String], failure: ReleaseInstallError) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw failure }
    }
}
