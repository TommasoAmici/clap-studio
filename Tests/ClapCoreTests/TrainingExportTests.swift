import Foundation
import Testing
@testable import ClapCore

@Suite struct TrainingExportTests {
    /// Parses embeddings.npy by hand: returns (rows, columns, values).
    private func readNpy(_ url: URL) throws -> (rows: Int, columns: Int, values: [Float]) {
        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(8)) == [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59, 1, 0], "magic and version 1.0")
        let headerLength = Int(data[8]) | Int(data[9]) << 8
        #expect((10 + headerLength) % 64 == 0, "the data starts on a 64-byte boundary")
        let header = String(decoding: data[10..<(10 + headerLength)], as: UTF8.self)
        #expect(header.contains("'descr': '<f4'") && header.contains("'fortran_order': False") && header.hasSuffix("\n"))
        let shape = try #require(header.range(of: #"\((\d+), (\d+)\)"#, options: .regularExpression))
        let numbers = header[shape].dropFirst().dropLast().split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces))! }
        let floats = VectorCodec.decodeFloat32(data.dropFirst(10 + headerLength))
        #expect(floats.count == numbers[0] * numbers[1])
        return (numbers[0], numbers[1], floats)
    }

    /// Minimal RFC 4180 reader for the checks below.
    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text), i = 0
        chars.append("\0")
        while i < chars.count - 1 {
            let c = chars[i]
            if quoted {
                if c == "\"", chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else if c == "\"" { quoted = false }
                else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(c) }
            i += 1
        }
        return rows
    }

    private struct Fixture { var store: LibraryStore; var ids: [String: Int64] }

    /// Samples: kick (automatic), snare (manual over an automatic Clap), odd name, unlabelled, long recording,
    /// old-model sample, USB-stick sample.
    private func fixture() throws -> Fixture {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/lib")
        let usb = try store.addRoot(path: "/usb", transient: true)
        let names = ["kick.wav", "snare.wav", "odd, \"name\"\nx.wav", "none.wav", "field.wav", "old.wav"]
        try store.sync(rootID: root.id, scanned: names.map { ScannedFile(relPath: $0, size: 1, mtime: 1) }) { "fp-\($0)" }
        try store.sync(rootID: usb.id, scanned: [ScannedFile(relPath: "stick.wav", size: 1, mtime: 1)]) { _ in nil }
        var ids: [String: Int64] = [:]
        var results: [IndexResult] = []
        for job in store.pendingJobs(limit: 100) {
            let name = job.url.lastPathComponent
            ids[name] = job.id
            let vector: [Float] = [Float(ids.count), 0.5, -1.25]
            results.append(.success(id: job.id, duration: name == "field.wav" ? 120 : 1, sampleRate: 44100, channels: 1,
                                    embedding: vector, fingerprint: "fp-\(name)",
                                    modelVersion: name == "old.wav" ? "old-model" : ClapEmbedder.versionTag))
        }
        try store.save(results: results)
        let categorizer = try Categorizer(embed: { _ in [1, 0, 0] }, categories: [("Kick", ["k"])])
        try store.categorize(with: categorizer)                       // everything gets Kick, automatically
        try store.db.run("UPDATE samples SET category = NULL WHERE id = ?", [.int(ids["none.wav"]!)])
        try store.db.run("UPDATE samples SET category = 'Clap' WHERE id = ?", [.int(ids["snare.wav"]!)])
        try store.setManualCategory(sampleID: ids["snare.wav"]!, "Snare")
        return Fixture(store: store, ids: ids)
    }

    @Test func exportsEmbeddingsAndLabelsInTheSameOrder() throws {
        let f = try fixture()
        let parent = TestSupport.tempDir()
        let summary = try TrainingExport.write(store: f.store, into: parent)

        // kick, snare and the oddly named file; not the unlabelled, long, old-model or USB samples.
        #expect(summary.rows == 3 && summary.manual == 1 && summary.automatic == 2)
        #expect(summary.skippedUncategorised == 1 && summary.skippedFieldRecordings == 1 && summary.skippedAutomatic == 0)

        let npy = try readNpy(summary.folder.appendingPathComponent("embeddings.npy"))
        #expect(npy.rows == 3 && npy.columns == 3)
        let csv = parseCSV(try String(contentsOf: summary.folder.appendingPathComponent("labels.csv"), encoding: .utf8))
        #expect(csv[0] == TrainingExport.columns)
        #expect(csv.count == 4 && csv.allSatisfy { $0.count == TrainingExport.columns.count })

        let byName = Dictionary(uniqueKeysWithValues: csv.dropFirst().map { ($0[3], $0) })
        let snare = try #require(byName["snare"])
        #expect(snare[4] == "Snare" && snare[5] == "manual" && snare[6] == "Clap", "the manual label wins; CLAP's is kept")
        #expect(byName["kick"]?[4] == "Kick" && byName["kick"]?[5] == "automatic")
        #expect(byName["kick"]?[1] == "/lib/kick.wav" && byName["kick"]?[2] == "kick.wav" && byName["kick"]?[8] == "fp-kick.wav")
        let odd = try #require(csv.dropFirst().first { $0[3].hasPrefix("odd") })
        #expect(odd[2] == "odd, \"name\"\nx.wav", "commas, quotes and line breaks survive")

        // Row i of the CSV is row i of the matrix.
        for row in csv.dropFirst() {
            let i = Int(row[0])!
            let id = f.ids[row[2]]!
            let stored = try f.store.embeddings(ids: [id]).flat
            #expect(Array(npy.values[(i * 3)..<(i * 3 + 3)]) == stored)
        }
    }

    @Test func manualLabelsOnlyKeepsTheUsersOwn() throws {
        let f = try fixture()
        let summary = try TrainingExport.write(store: f.store, into: TestSupport.tempDir(), manualOnly: true)
        #expect(summary.rows == 1 && summary.manual == 1 && summary.automatic == 0)
        #expect(summary.skippedAutomatic == 2)
        let csv = parseCSV(try String(contentsOf: summary.folder.appendingPathComponent("labels.csv"), encoding: .utf8))
        #expect(csv.dropFirst().map { $0[3] } == ["snare"])
        #expect(try readNpy(summary.folder.appendingPathComponent("embeddings.npy")).rows == 1)
    }

    @Test func metadataDescribesTheExportAndFoldersAreNeverReused() throws {
        let f = try fixture()
        let parent = TestSupport.tempDir()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try TrainingExport.write(store: f.store, into: parent, date: date)
        let second = try TrainingExport.write(store: f.store, into: parent, date: date)
        #expect(first.folder != second.folder && first.folder.lastPathComponent.hasPrefix("clap-training-export-"))
        #expect(FileManager.default.fileExists(atPath: first.folder.appendingPathComponent("embeddings.npy").path))

        let data = try Data(contentsOf: first.folder.appendingPathComponent("metadata.json"))
        let info = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(info["model_version"] as? String == ClapEmbedder.versionTag)
        #expect(info["rows"] as? Int == 3 && info["embedding_dimension"] as? Int == 3)
        #expect((info["categories"] as? [String])?.contains("Kick") == true)
    }

    @Test func anEmptyLibraryStillWritesAValidMatrix() throws {
        let (store, _) = try TestSupport.makeStore()
        let summary = try TrainingExport.write(store: store, into: TestSupport.tempDir())
        #expect(summary.rows == 0)
        let npy = try readNpy(summary.folder.appendingPathComponent("embeddings.npy"))
        #expect(npy.rows == 0 && npy.columns == 512 && npy.values.isEmpty)
    }
}
