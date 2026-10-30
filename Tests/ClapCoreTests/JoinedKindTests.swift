import Foundation
import Testing
@testable import ClapCore

@Suite struct JoinedKindTests {
    private func scanned(_ url: URL) throws -> ScannedFile {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return ScannedFile(relPath: url.lastPathComponent,
                           size: (attrs[.size] as? NSNumber)?.int64Value ?? 0,
                           mtime: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
    }

    private func retime(_ url: URL, to seconds: Double) throws {
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: url.path)
    }
    @Test func joinedFilesAreSeparateFromOtherSampleTypes() {
        var sound = SampleRecord(id: 1, rootID: 1, rootPath: "/tmp", relPath: "a.wav", name: "a", ext: "wav",
                                 duration: 45, sampleRate: 44_100, channels: 1, size: 1, mtime: 0,
                                 status: .ok, useCount: 0, lastUsed: nil, cueCount: 0)
        sound.isJoined = true
        sound.isLoop = true
        var filter = DescriptorFilter()
        #expect(filter.matches(sound), "All still includes joined samples.")
        for kind in [DescriptorFilter.Kind.oneShot, .loop, .fieldRecording] {
            filter.kind = kind
            #expect(!filter.matches(sound), "A joined file does not masquerade as another sample type.")
        }
        filter.kind = .joined
        #expect(filter.matches(sound))
        sound.isJoined = false
        #expect(!filter.matches(sound), "The Joined filter excludes ordinary samples.")
    }

    @Test func indexedJoinedFilesStayJoinedWhenRenamed() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try store.addRoot(path: dir.path)
        let original = TestSupport.write([1, 2], to: dir.appendingPathComponent("Joined.wav"))
        let source = JoinSource(url: dir.appendingPathComponent("source.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: original, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])], sources: [source])
        try store.sync(rootID: root.id, scanned: [try scanned(original)]) { _ in FileFingerprint.compute(url: original) }
        #expect(store.loadSamples().first?.isJoined == true, "An indexed output is recognised as joined.")
        let renamed = dir.appendingPathComponent("renamed.wav")
        try FileManager.default.moveItem(at: original, to: renamed)
        try store.sync(rootID: root.id, scanned: [try scanned(renamed)]) { _ in FileFingerprint.compute(url: renamed) }
        let moved = try #require(store.loadSamples().first)
        #expect(moved.name == "renamed" && moved.isJoined, "A recognised rename carries its links with it.")
        #expect(store.joinedParts(for: moved.url).map(\.name) == ["source"])
    }
    @Test func noncanonicalRootStillRecognisesJoinedFiles() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try store.addRoot(path: dir.appendingPathComponent("sub/..", isDirectory: true).path + "/")
        let output = TestSupport.write([1, 2], to: dir.appendingPathComponent("Joined.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(store.loadSamples().first?.isJoined == true, "Trailing slashes and parent components do not hide joined files.")
    }

    @Test func classifyingPublishedFilesKeepsLaterLibraryEdits() {
        var sound = SampleRecord(id: 9, rootID: 2, rootPath: "/tmp", relPath: "Joined.wav", name: "Joined", ext: "wav",
                                 duration: 1, sampleRate: 44_100, channels: 1, size: 1, mtime: 0,
                                 status: .ok, useCount: 0, lastUsed: nil, cueCount: 0)
        sound.favorite = true
        sound.tags = ["edited after export started"]
        var current = [sound]
        let changed = JoinedLibrary.markJoined(in: &current, pathsByRoot: [2: ["Joined.wav"]])
        #expect(changed == [9] && current[0].isJoined, "The newly joined file becomes available to the filter.")
        #expect(current[0].favorite && current[0].tags == ["edited after export started"],
                "Classifying never replaces edits made while the file was being exported.")
        #expect(JoinedLibrary.markJoined(in: &current, pathsByRoot: [2: ["Joined.wav"]]).isEmpty,
                "Refreshing the same output does not change it again.")
    }

    @Test func replacingJoinedAudioDoesNotKeepItsOldSources() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try store.addRoot(path: dir.path)
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("Joined.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let first = try scanned(output)
        try store.sync(rootID: root.id, scanned: [first]) { _ in FileFingerprint.compute(url: output) }
        try retime(output, to: first.mtime + 2)
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(store.isJoinedFile(at: output), "A timestamp-only change keeps the original links.")
        try Data([4, 5, 6]).write(to: output)
        try retime(output, to: first.mtime + 4)
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(!store.isJoinedFile(at: output), "Different audio at the same path is not the old joined file.")
        #expect(store.joinedParts(for: output).isEmpty, "The replacement must not inherit old source links.")
    }

    @Test func replacementBeforeFirstIndexDoesNotInheritSources() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("Joined.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        try Data([7, 8, 9]).write(to: output)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(store.loadSamples().first?.isJoined == false, "A replacement before indexing is an ordinary sample.")
        #expect(store.joinedParts(for: output).isEmpty, "It cannot inherit links from the exported file it replaced.")
    }
    @Test func unreadableJoinedFileIsHiddenUntilVerified() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("Joined.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let root = try store.addRoot(path: dir.path)
        let file = try scanned(output)
        try FileManager.default.removeItem(at: output)
        try store.sync(rootID: root.id, scanned: [file]) { _ in nil }
        #expect(store.loadSamples().first?.isJoined == false, "Unverified audio is not attributed to old sources.")
        #expect(store.joinedParts(for: output).count == 1, "The links remain available for a later retry.")
        try Data([1, 2, 3]).write(to: output)
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(store.loadSamples().first?.isJoined == true, "A later successful check restores the joined classification.")
    }

    @Test func appAuthoredMetadataWritesRefreshTheFingerprint() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("Joined.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        let id = try #require(store.loadSamples().first?.id)
        try Data([4, 5, 6]).write(to: output)
        let written = try scanned(output)
        try store.updateFileAttributes(sampleID: id, size: written.size, mtime: written.mtime, fingerprint: FileFingerprint.compute(url: output))
        try retime(output, to: written.mtime + 2)
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(store.isJoinedFile(at: output), "A verified app-authored metadata write keeps source links.")
    }

    @Test func renamedOutputKeepsItsOwnLinksWhenTheDestinationWasPreviouslyJoined() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("old.wav"))
        let destination = TestSupport.write([4, 5, 6], to: dir.appendingPathComponent("new.wav"))
        let region = JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)
        try store.recordJoinedOutputs([JoinedOutput(url: old, regions: [region])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("first.wav"))])
        try store.recordJoinedOutputs([JoinedOutput(url: destination, regions: [region])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("second.wav"))])
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: [try scanned(old)]) { _ in FileFingerprint.compute(url: old) }
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: old, to: destination)
        try store.sync(rootID: root.id, scanned: [try scanned(destination)]) { _ in FileFingerprint.compute(url: destination) }
        #expect(store.joinedParts(for: destination).map(\.name) == ["first"],
                "A recognised moved file carries its own sources to the reused destination name.")
        #expect(store.loadSamples().first?.isJoined == true)
    }

    @Test func appWriteWithoutReadableFingerprintCanRecover() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("Joined.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let root = try store.addRoot(path: dir.path)
        let original = try scanned(output)
        try store.sync(rootID: root.id, scanned: [original]) { _ in FileFingerprint.compute(url: output) }
        let id = try #require(store.loadSamples().first?.id)
        try store.updateFileAttributes(sampleID: id, size: original.size, mtime: original.mtime, fingerprint: nil)
        #expect(!store.isJoinedFile(at: output) && store.joinedParts(for: output).count == 1,
                "Links stay saved but hidden while the app-authored rewrite cannot be fingerprinted.")
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(store.isJoinedFile(at: output), "A later readable scan restores links when the bytes still match.")
    }

    @Test func writingCuesKeepsJoinedSourceLinks() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("Joined.wav")
        try writeTestWav(output, seconds: 0.1) { _ in 0.2 }
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in FileFingerprint.compute(url: output) }
        let sample = try #require(store.loadSamples().first)
        try store.insertCue(sampleID: sample.id, frame: 100, label: "Cue")
        try store.writeCuesToFile(sample: sample, keepBackup: false)
        let written = try #require(FolderScanner.scan(root: dir).first)
        try retime(output, to: written.mtime + 2)
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(store.isJoinedFile(at: output) && store.joinedParts(for: output).count == 1,
                "The app's verified cue write does not discard the joined source links.")
    }

    @Test func migrationKeepsEarlierLinksUntilTheyCanBeVerified() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("Joined.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let root = try store.addRoot(path: dir.path)
        // Recreate the version 15 table shape with the existing links intact.
        try store.db.exec("ALTER TABLE joined_files DROP COLUMN verified")
        try store.db.exec("ALTER TABLE joined_files DROP COLUMN fingerprint")
        try store.db.exec("DROP INDEX collections_parent")
        try store.db.exec("ALTER TABLE collections DROP COLUMN parent_id")
        try store.db.exec("PRAGMA user_version = 15")
        let migrated = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        #expect(!migrated.isJoinedFile(at: output) && migrated.joinedParts(for: output).count == 1,
                "Earlier links stay saved but hidden until the file is checked.")
        try migrated.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(migrated.isJoinedFile(at: output) && migrated.joinedParts(for: output).count == 1,
                "A readable scan restores the earlier links without changing them.")
    }

    @Test func changingOnlyTheMiddleDoesNotKeepOldSources() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("Joined.wav")
        var bytes = Data(repeating: 1, count: 16_384)
        try bytes.write(to: output)
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let root = try store.addRoot(path: dir.path)
        let original = try scanned(output)
        try store.sync(rootID: root.id, scanned: [original]) { _ in FileFingerprint.compute(url: output) }
        let cheap = FileFingerprint.compute(url: output)
        bytes[8_192] = 2
        try bytes.write(to: output)
        try retime(output, to: original.mtime + 2)
        #expect(FileFingerprint.compute(url: output) == cheap, "The ordinary move fingerprint does not inspect the middle.")
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(!store.isJoinedFile(at: output), "Changing a middle sound cannot keep the former source links.")
    }

    @Test func middleChangeBeforeFirstIndexDoesNotKeepOldSources() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("Joined.wav")
        var bytes = Data(repeating: 1, count: 16_384)
        try bytes.write(to: output)
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let cheap = FileFingerprint.compute(url: output)
        bytes[8_192] = 2
        try bytes.write(to: output)
        #expect(FileFingerprint.compute(url: output) == cheap, "The ordinary move fingerprint misses this edit.")
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(store.loadSamples().first?.isJoined == false && store.joinedParts(for: output).isEmpty,
                "A pre-index middle edit must not inherit the exported file's source links.")
    }

    @Test func replacementDuringHashCannotProduceAVerifiedDigest() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("Joined.wav")
        let original = Data(repeating: 1, count: 1_048_577)
        let replacement = Data(repeating: 2, count: original.count)
        try original.write(to: output)
        let originalTime = try scanned(output).mtime
        var changed = false
        let result = JoinedFileFingerprint.snapshot(url: output, onChunk: {
            guard !changed else { return }
            changed = true
            try? replacement.write(to: output, options: .atomic)
            try? retime(output, to: originalTime)
        })
        #expect(changed && result == nil, "Replacing the path during hashing cannot yield a verified digest.")
    }

    @Test func replacementAfterHashStaysUnverifiedUntilRescan() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("Joined.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let root = try store.addRoot(path: dir.path)
        let original = try scanned(output)
        try store.sync(rootID: root.id, scanned: [original]) { _ in FileFingerprint.compute(url: output) }
        let snapshot = try #require(JoinedFileFingerprint.snapshot(url: output))
        try Data([4, 5, 6]).write(to: output, options: .atomic)
        try retime(output, to: original.mtime)
        try store.db.transaction {
            try store.verifyJoinedFile(at: output, snapshot: snapshot, scanned: original)
        }
        #expect(!store.isJoinedFile(at: output) && store.joinedParts(for: output).count == 1,
                "A replaced inode hides links without prematurely discarding them.")
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(!store.isJoinedFile(at: output) && store.joinedParts(for: output).isEmpty,
                "The next readable rescan confirms the replacement and forgets old links.")
    }

    @Test func changedScanStateCannotVerifyAnOtherwiseStableHash() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("Joined.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let prior = try scanned(output)
        try retime(output, to: prior.mtime + 2)
        let snapshot = try #require(JoinedFileFingerprint.snapshot(url: output))
        try store.db.transaction { try store.verifyJoinedFile(at: output, snapshot: snapshot, scanned: prior) }
        #expect(!store.isJoinedFile(at: output) && store.joinedParts(for: output).count == 1,
                "A stable hash with newer file attributes stays unverified until the next scan.")
    }

    @Test func cancellingJoinedVerificationLeavesLinksAndScanUntouched() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("Joined.wav")
        try Data(repeating: 1, count: 2_097_153).write(to: output)
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let root = try store.addRoot(path: dir.path)
        let file = try scanned(output)
        var checks = 0
        #expect(throws: CancellationError.self) {
            try store.sync(rootID: root.id, scanned: [file], isCancelled: {
                checks += 1
                return checks >= 3
            }) { _ in FileFingerprint.compute(url: output) }
        }
        #expect(store.isJoinedFile(at: output) && store.joinedParts(for: output).count == 1,
                "Stopping verification must preserve the saved links.")
        #expect(store.loadSamples().isEmpty, "A cancelled scan does not commit a partial library update.")
    }

    @Test func unverifiedAppWriteDoesNotTrustChangedBytes() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("Joined.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        let id = try #require(store.loadSamples().first?.id)
        try Data([4, 5, 6]).write(to: output)
        let changed = try scanned(output)
        try store.updateFileAttributes(sampleID: id, size: changed.size, mtime: changed.mtime, fingerprint: nil)
        #expect(!store.isJoinedFile(at: output), "An unverified rewrite stays hidden.")
        try store.sync(rootID: root.id, scanned: [try scanned(output)]) { _ in FileFingerprint.compute(url: output) }
        #expect(store.joinedParts(for: output).isEmpty,
                "Unknown changed bytes cannot be accepted as the previous joined file.")
    }

}
