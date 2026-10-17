import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidPoolTests {
    private let fm = FileManager.default

    private func source(_ dir: URL, _ name: String) throws -> SquidSource {
        let url = dir.appendingPathComponent(name + ".wav")
        try writeTestWav(url, seconds: 0.2, sampleRate: 44_100) { _ in 0.5 }
        return SquidSource(file: url, name: name)
    }

    /// A stick whose Pool holds `kick` at the top, two samples in Breaks, one in Breaks/707 and an empty Drums folder.
    private func stickWithPool() throws -> URL {
        let dir = TestSupport.tempDir()
        let volume = TestSupport.tempDir()
        try fm.createDirectory(at: SquidStick.rootURL(volume: volume), withIntermediateDirectories: true)
        try SquidExporter.exportToPool([try source(dir, "kick")], toVolume: volume)
        try SquidExporter.exportToPool([try source(dir, "hat"), try source(dir, "ride")], subfolder: "Breaks", toVolume: volume)
        try SquidExporter.exportToPool([try source(dir, "amen")], subfolder: "Breaks/707", toVolume: volume)
        try fm.createDirectory(at: SquidStick.rootURL(volume: volume).appendingPathComponent("Pool/Drums"), withIntermediateDirectories: true)
        return volume
    }

    @Test func poolFoldersAreReadWithTheirSamples() throws {
        let contents = SquidStick.read(volume: try stickWithPool())
        #expect(contents.hasPool)
        #expect(contents.poolFolders.map(\.name) == ["Breaks", "Drums"], "sub-folders hang off their parent, not the top level")
        let breaks = try #require(contents.poolFolders.first)
        #expect(breaks.path == ["Breaks"] && breaks.sampleCount == 2, "only the samples directly inside are counted")
        #expect(breaks.children.map(\.path) == [["Breaks", "707"]] && breaks.children.first?.sampleCount == 1)
        #expect(contents.poolFolders.last?.sampleCount == 0, "an empty folder is still listed")
    }

    @Test func everyPoolFolderCanBeListedAsAPath() throws {
        let contents = SquidStick.read(volume: try stickWithPool())
        #expect(contents.poolFolderPaths == [["Breaks"], ["Breaks", "707"], ["Drums"]], "parents come before their children")
    }

    @Test func aStickWithoutAPoolHasNoFolders() throws {
        let volume = TestSupport.tempDir()
        try fm.createDirectory(at: SquidStick.rootURL(volume: volume), withIntermediateDirectories: true)
        let contents = SquidStick.read(volume: volume)
        #expect(!contents.hasPool && contents.poolFolders.isEmpty && contents.poolFolderPaths.isEmpty)
    }

    // MARK: where a sample sits

    @Test func aPoolSampleBelongsToEveryFolderAboveIt() {
        let deep = SquidLayout.location(ofRelativePath: "Pool/Breaks/707/amen.wav")
        #expect(SquidLayout.location(deep, isInPoolFolder: []), "the whole Pool")
        #expect(SquidLayout.location(deep, isInPoolFolder: ["Breaks"]))
        #expect(SquidLayout.location(deep, isInPoolFolder: ["breaks", "707"]), "a FAT32 stick does not tell the case apart")
        #expect(!SquidLayout.location(deep, isInPoolFolder: ["Drums"]))
        #expect(!SquidLayout.location(deep, isInPoolFolder: ["Breaks", "707", "more"]), "a folder deeper than the sample")
        #expect(!SquidLayout.location(SquidLayout.location(ofRelativePath: "Bank 1/1/a.wav"), isInPoolFolder: []), "banks are not the Pool")
    }

    // MARK: the outline shown in the main area

    private typealias Row = PoolRow<String>
    private let tree = [
        SquidPoolFolder(name: "Breaks", path: ["Breaks"], sampleCount: 2,
                        children: [SquidPoolFolder(name: "707", path: ["Breaks", "707"], sampleCount: 1)]),
        SquidPoolFolder(name: "Drums", path: ["Drums"], sampleCount: 0),
    ]
    private let items: [(folder: [String], item: String)] = [
        ([], "kick"), (["Breaks"], "hat"), (["Breaks", "707"], "amen"), (["Breaks"], "ride"), ([], "snare"),
    ]

    private func describe(_ rows: [Row]) -> [String] {
        rows.map {
            switch $0 {
            case .folder(let folder, let depth, let expanded): return "\(String(repeating: " ", count: depth))\(expanded ? "v" : ">") \(folder.name)"
            case .sample(let item): return item
            }
        }
    }

    @Test func theOutlineListsLooseSamplesFirstThenEachFolderWithItsContents() {
        let rows = PoolOutline.rows(root: [], folders: tree, items: items, collapsed: [])
        #expect(describe(rows) == ["kick", "snare", "v Breaks", "hat", "ride", " v 707", "amen", "v Drums"],
                "samples keep the order they came in; an empty folder still shows")
    }

    @Test func aCollapsedFolderHidesEverythingInsideIt() {
        let rows = PoolOutline.rows(root: [], folders: tree, items: items, collapsed: ["breaks"])
        #expect(describe(rows) == ["kick", "snare", "> Breaks", "v Drums"], "its sub-folders go with it")
        let inner = PoolOutline.rows(root: [], folders: tree, items: items, collapsed: ["breaks/707"])
        #expect(describe(inner) == ["kick", "snare", "v Breaks", "hat", "ride", " > 707", "v Drums"], "only the inner one closes")
    }

    @Test func anOutlineOfOneFolderStartsFromThatFolder() {
        let rows = PoolOutline.rows(root: ["Breaks"], folders: tree[0].children, items: Array(items.dropFirst()).filter { $0.folder.first == "Breaks" },
                                    collapsed: [])
        #expect(describe(rows) == ["hat", "ride", "v 707", "amen"], "its own samples first, and folders drawn from depth 0")
    }

    @Test func aSampleInAFolderTheScanMissedIsStillShown() {
        let rows = PoolOutline.rows(root: [], folders: tree, items: items + [(["New"], "late")], collapsed: [])
        #expect(describe(rows).last == "late", "nothing is hidden because the stick changed between the scan and the index")
    }

    @Test func hiddenFilesAreNotCountedAsSamples() throws {
        let volume = try stickWithPool()
        let breaks = SquidStick.rootURL(volume: volume).appendingPathComponent("Pool/Breaks")
        try Data().write(to: breaks.appendingPathComponent("._hat.wav"))
        try Data().write(to: breaks.appendingPathComponent(".DS_Store"))
        #expect(SquidStick.read(volume: volume).poolFolders.first?.sampleCount == 2, "macOS leaves such files on FAT32 sticks")
    }
}
