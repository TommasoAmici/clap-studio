import AppKit
import ClapCore
import Observation
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case library = "Library", map = "Map"
    var id: String { rawValue }
}

enum SmartFilter: String, CaseIterable, Identifiable {
    case all = "All Samples", mostUsed = "Most Used", neverUsed = "Never Used", recentlyGrabbed = "Recently Grabbed", favorites = "Favorites", hidden = "Hidden"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: return "waveform"
        case .mostUsed: return "flame"
        case .neverUsed: return "circle.dashed"
        case .recentlyGrabbed: return "clock"
        case .favorites: return "star"
        case .hidden: return "eye.slash"
        }
    }
}

struct SimilarResult: Identifiable {
    let sample: SampleRecord
    let score: Float
    var id: Int64 { sample.id }
}

struct ClusterInfo: Identifiable, Equatable {
    let id: Int
    let count: Int
    let label: String
    let detail: String      // what the cluster holds, as a tooltip
}

/// Central app state. Heavy work runs off the main actor; results are published here.
@MainActor @Observable
final class AppModel {
    // MARK: services
    @ObservationIgnored var store: LibraryStore?
    @ObservationIgnored var analyzer: LibraryAnalyzer?
    @ObservationIgnored var cueEditor: CueEditor?
    @ObservationIgnored var cueSync: CueFileSync?
    @ObservationIgnored var embedder: EmbeddingProvider?
    @ObservationIgnored let player = SamplePlayer()
    @ObservationIgnored lazy var drumMachine: DrumMachine = makeDrumMachine()
    @ObservationIgnored var cancelToken = CancelToken()
    @ObservationIgnored var textSearcher: TextSearcher?
    @ObservationIgnored var soundSearchTask: Task<Void, Never>?
    @ObservationIgnored var lastGrab: [Int64: Date] = [:]
    @ObservationIgnored var recentDragAt = Date.distantPast
    @ObservationIgnored var recentDrags: [Int64] = []      // samples the user started dragging, newest last

    // MARK: library data
    var roots: [RootRecord] = [] { didSet { if oldValue.map(\.path) != roots.map(\.path) { restartWatcher() } } }
    var samples: [SampleRecord] = []
    var sampleByID: [Int64: SampleRecord] = [:]
    var visible: [SampleRecord] = []
    var filterVersion = 0       // bumps whenever `visible` is recomputed (the map follows it)
    var filtersActive = false
    var folderTree: [FolderNode] = []
    var hiddenCount = 0
    var mapColorMode: MapColorMode = .cluster { didSet { refreshMapColoring() } }
    var mapColoring: MapColoring?
    var mapColorVersion = 0
    var mapAxes: (x: MapProperty, y: MapProperty)? { didSet { refreshMapLayout() } }
    var axisLayout: MapAxes.Layout?
    var mapSelection: [Int64] = []          // dots picked with the lasso
    var aspectWeights = AspectWeights() { didSet {
        if let id = selectedID { sweepList = []; updateSimilar(for: id) }
        if let reference = exampleQuery?.referenceID { showSimilar(to: reference) }
    } }
    var tagFilter: String? { didSet { refilter() } }
    var tagCounts: [(name: String, count: Int)] = []
    var tagPromptTargets: [Int64]?            // non-nil while the "add tag" prompt is open
    var showExport = false
    @ObservationIgnored var folderWatcher: FolderWatcher?
    @ObservationIgnored var rescanTask: Task<Void, Never>?
    var undoStack: [LibraryEdit] = []
    var redoStack: [LibraryEdit] = []
    var sweepList: [Int64] = []             // the neighbours being stepped through with ← →
    var exampleQuery: ExampleQuery?          // set while the list shows sounds similar to a dropped file
    @ObservationIgnored var exampleSearcher: ExampleSearcher?
    /// Segments of field recordings, shared by every search that reports where in a recording a sound is.
    @ObservationIgnored let segmentCache = SegmentIndexCache()
    var collections: [CollectionRecord] = []
    var collectionSelection: Int64? { didSet { reloadCollections(); refilter() } }
    var collectionMembers: Set<Int64> = []
    var newCollectionSeed: [Int64]?       // non-nil while the "new collection" prompt is open
    var duplicateGroups: [DuplicateGroup]?
    var duplicateSearchRunning = false
    var showDuplicates = false
    var showInsights = false
    var showKit = false
    var kitSlots: [KitSlot] = []
    var kitChoice: [String: Int] = [:]
    var trims: [Int64: SampleTrim] = [:]   // non-destructive start/end per sample
    var exportIDs: [Int64]?                // set when the export sheet was opened for specific samples
    var showDrums = false { didSet { if showDrums != oldValue { storeDrumPattern() } } }
    /// The groove picked in the drum machine (remembered between launches); nil uses the plain starter rhythms.
    var drumPresetID: String? { didSet { storeDrumGrooves() } }
    /// Grooves the user saved from their own patterns.
    var userDrumPresets: [DrumPreset] = [] { didSet { storeDrumGrooves() } }
    var drumPattern = DrumPattern() { didSet { if drumPattern != oldValue { pushDrumPattern(); updateDrumTracks(); storeDrumPattern() } } }
    @ObservationIgnored var drumSourcesReady = false      // the saved pattern's sounds have been matched to the library
    var drumTracks: [Int64: Int] = [:]     // sample id -> its (first) drum track number, 1-based; for highlighting
    var dropZones: [DropZone: CGRect] = [:]     // where dropped files are taken, in window coordinates
    var dropHover: DropZone?                    // the place a drag is currently over
    var drumStep: Int?                     // step currently sounding, nil when stopped
    var drumPlaying = false
    var categoryCounts: [(name: String, count: Int)] = []   // sidebar; only categories that have samples
    var birdsRevision = 0                                   // bumped when birds or places change, to reload the section
    var moodCounts: [(name: String, count: Int)] = []       // sidebar; only moods that have samples

    // MARK: developer export
    var exportManualLabelsOnly = UserDefaults.standard.bool(forKey: "developer.exportManualOnly") {
        didSet { UserDefaults.standard.set(exportManualLabelsOnly, forKey: "developer.exportManualOnly") }
    }
    var trainingExportRunning = false
    var trainingExportResult: TrainingExportResult?

    // MARK: Squid Salmple (USB sticks)
    /// Connected drives that hold an `ALM022` folder, so are meant for the module.
    var usbDrives: [UsbDrive] = []
    /// Squid features appear whenever such a drive is connected, and disappear with the last one.
    var squidEnabled: Bool { !usbDrives.isEmpty }
    var usbContents: [String: SquidStickContents] = [:]      // by drive id
    var usbSamples: [SampleRecord] = []                      // analysed, but not part of the library
    var usbSelection: UsbSelection? { didSet { if usbSelection != oldValue { refilter() } } }
    var showSquidExport = false
    var squidItems: [Int64] = []                              // what the export sheet will send, in order
    var squidTarget = SquidTarget()
    @ObservationIgnored var usbSampleIDs: Set<Int64> = []
    @ObservationIgnored var usbObservers: [NSObjectProtocol] = []
    @ObservationIgnored var usbRefreshTask: Task<Void, Never>?
    @ObservationIgnored var usbIndexQueued = false

    // MARK: filters
    var searchFocusRequests = 0                             // Cmd+F bumps this; the search field takes focus
    var searchText = "" { didSet { if !searchText.isEmpty { exampleQuery = nil }; scheduleSoundSearch(); refilter() } }
    var textSearchAvailable = false
    var soundScores: [Int64: Float] = [:]       // semantic similarity of every sample to `soundScoresQuery`
    var soundScoresQuery = ""
    var soundSegments: [Int64: SegmentMatch] = [:]   // where in each field recording `soundScoresQuery` matches best
    var smartFilter: SmartFilter = .all { didSet { refilter() } }
    var descriptorFilter = DescriptorFilter() { didSet { refilter() } }
    var folderSelection: String? { didSet { refilter() } }   // FolderNode.id, nil = everything
    var sortOrder = [KeyPathComparator(\SampleRecord.name, comparator: .localizedStandard)] { didSet {
        // Choosing a column to sort by ends the shuffle.
        if shuffleSeed != nil, sortOrder != oldValue { shuffleSeed = nil } else { refilter() }
    } }
    var shuffleSeed: UInt64? { didSet { refilter() } }      // non-nil while the list is in a random order

    // MARK: selection and similarity
    var viewMode: ViewMode = .library
    var selectedID: Int64?
    var tableSelection: Set<Int64> = []     // rows highlighted in the list (more than one for batch actions)
    var similar: [SimilarResult] = []
    var similarRows: [Int] = []
    var cues: [CuePoint] = []
    var cueSyncIssues: [Int64: String] = [:]
    var waveform: [Float] = []
    var selectedCueID: Int64?
    /// Frame (in the file's own sample rate) where the user last clicked the waveform to audition.
    /// Kept until the next click or sample change so a cue can be set exactly there, even after playback moves on.
    var startMarkerFrame: Int64?
    var playback = PlaybackState()
    var autoplay = true
    var project = ProjectSettings() { didSet { saveProjectSettings(); if project.bpm != oldValue.bpm { drumMachine.bpm = drumTempo } } }
    var hoverPlay = true
    var volume: Float = 0.9 { didSet { player.volume = volume } }

    // MARK: map and analysis
    var snapshot: AnalysisSnapshot?
    var mapVersion = 0          // bumps when positions change (map refits the view)
    var clusterVersion = 0      // bumps when colours change
    var clusterCount = 12
    var clusterInfo: [ClusterInfo] = []
    var hoverRow: Int?

    // MARK: status
    var isIndexing = false
    var isListeningForBirds = false
    var progress: IndexProgress?
    var statusMessage = ""
    var errorMessage: String?
    var modelNote = ""
    var usingFallbackModel = false
    var failedCount = 0

    init() {
        player.volume = volume
        player.onStateChange = { [weak self] state in
            Task { @MainActor in self?.playback = state }
        }
    }

    var selectedSample: SampleRecord? { selectedID.flatMap { sampleByID[$0] } }

    // MARK: startup

    /// Opens the persistent store and shows cached data immediately; no audio or ML work happens here.
    func bootstrap() {
        loadProjectSettings()
        loadDrumGrooves()
        loadDrumPattern()
        do {
            let store = try LibraryStore(path: try LibraryStore.defaultURL().path)
            self.store = store
            analyzer = LibraryAnalyzer(store: store)
            cueEditor = CueEditor(store: store)
            exampleSearcher = ExampleSearcher(store: store, segments: segmentCache)
            let sync = CueFileSync(store: store) { [weak self] outcome in
                Task { @MainActor in self?.handleCueSync(outcome) }
            }
            cueSync = sync
            sync.syncAllDirty()
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                   queue: nil) { _ in sync.flush() }
            try? store.purgeTransientRoots()     // a stick from an earlier run is not necessarily plugged in now
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                   queue: nil) { _ in try? store.purgeTransientRoots() }
            roots = store.roots()
            collections = store.collections()
            reloadSamples()
            failedCount = store.failedCount()
            if let n = store.meta("cluster_k").flatMap(Int.init) { clusterCount = n }
            if let version = store.meta("model_version") {
                snapshot = analyzer?.loadSnapshot(modelVersion: version)
                afterSnapshotChange()
            }
            prepareTextSearch()
            // Developer convenience: `ClapStudio --add-folder /path/to/samples`
            let args = CommandLine.arguments
            if let flag = args.firstIndex(of: "--add-folder"), flag + 1 < args.count {
                let url = URL(fileURLWithPath: args[flag + 1])
                if let root = try? store.addRoot(path: url.resolvingSymlinksInPath().path) { roots = store.roots(); _ = root }
            }
            if !roots.isEmpty { startIndexing() }
            watchUsbDrives()
        } catch {
            errorMessage = "Could not open the library database: \(error)"
        }
    }

    // MARK: folders

    func addFolder(_ url: URL) {
        guard let store else { return }
        do {
            let root = try store.addRoot(path: url.resolvingSymlinksInPath().path)
            roots = store.roots()
            if !roots.contains(where: { $0.id == root.id }) { roots.append(root) }
            startIndexing()
        } catch { errorMessage = "Could not add folder: \(error)" }
    }

    func removeRoot(_ root: RootRecord) {
        guard let store else { return }
        try? store.removeRoot(id: root.id)
        roots = store.roots()
        folderSelection = nil
        reloadSamples()
        if let version = store.meta("model_version") {
            snapshot = analyzer?.loadSnapshot(modelVersion: version)
            afterSnapshotChange()
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Index Folder"
        panel.message = "Choose a folder of audio samples. Files are only read, never moved or changed."
        if panel.runModal() == .OK, let url = panel.url { addFolder(url) }
    }

    // MARK: data loading

    func reloadSamples() {
        guard let store else { return }
        samples = store.loadSamples()
        usbSamples = squidEnabled ? store.loadTransientSamples() : []
        usbSampleIDs = Set(usbSamples.map(\.id))
        trims = store.trims()
        sampleByID = Dictionary(uniqueKeysWithValues: (samples + usbSamples).map { ($0.id, $0) })
        folderTree = FolderNode.build(roots: roots, samples: samples)
        updateCategoryCounts()
        updateMoodCounts()
        buildClusterInfo()
        updateHiddenCount()
        updateTagCounts()
        if mapColorMode != .cluster { refreshMapColoring() }
        if mapAxes != nil { refreshMapLayout() }
        refilter()
        if let id = selectedID, sampleByID[id] == nil { selectedID = nil }
        restoreDrumSounds()
    }

    func refilter() {
        // While a semantic search is running, keep showing the previous results (list and map)
        // instead of flashing a partial or empty set; the finished search calls refilter() again.
        if searchPending { return }
        let base = usbSelection.map(usbSamples(in:)) ?? samples
        var list = smartFilter == .hidden ? base.filter(\.hidden) : base.filter { !$0.hidden }
        switch smartFilter {
        case .all, .hidden: break
        case .favorites: list = list.filter(\.favorite)
        case .mostUsed: list = list.filter { $0.useCount > 0 }
        case .neverUsed: list = list.filter { $0.useCount == 0 }
        case .recentlyGrabbed: list = list.filter { $0.lastUsed != nil }
        }
        if collectionSelection != nil { list = list.filter { collectionMembers.contains($0.id) } }
        if let sel = folderSelection, let node = FolderNode.find(sel, in: folderTree) {
            list = list.filter { $0.rootID == node.rootID && ($0.relPath.hasPrefix(node.path) || node.path.isEmpty) }
        }
        if descriptorFilter.isActive { list = list.filter(descriptorFilter.matches) }
        if let tag = tagFilter { list = list.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } } }
        if let example = exampleQuery {
            let ranked = list.filter { example.scores[$0.id] != nil }.sorted { example.scores[$0.id]! > example.scores[$1.id]! }
            publish(ranked)
            return
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let named = Set(list.filter {
                $0.name.localizedCaseInsensitiveContains(query) || $0.relPath.localizedCaseInsensitiveContains(query)
                    || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }.map(\.id))
            if soundSearchActive && soundScoresQuery == query {
                // One search box: file-name matches first, then sounds that match the description.
                let order = HybridSearch.rank(ids: list.map(\.id), nameMatches: named, scores: soundScores)
                publish(order.compactMap { sampleByID[$0] })
                return
            }
            list = list.filter { named.contains($0.id) }     // semantic search unavailable: names only
        }
        switch smartFilter {
        case .mostUsed: list.sort { $0.useCount > $1.useCount }
        case .recentlyGrabbed: list.sort { ($0.lastUsed ?? 0) > ($1.lastUsed ?? 0) }
        default:
            if let seed = shuffleSeed { list = SeededShuffle.order(list, seed: seed) { $0.id } }
            else { list.sort(using: sortOrder) }
        }
        publish(list)
    }

    private func publish(_ list: [SampleRecord]) {
        visible = list
        filtersActive = usbSelection != nil || smartFilter != .all || tagFilter != nil || exampleQuery != nil || collectionSelection != nil || hiddenCount > 0 || folderSelection != nil || descriptorFilter.isActive || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        filterVersion += 1
    }

    /// Which map dots pass the sidebar and search filters; nil when nothing is filtered.
    func mapMask(for snapshot: AnalysisSnapshot) -> [Bool]? {
        let placed = axisLayout?.valid
        guard filtersActive || placed != nil else { return nil }
        let allowed = Set(visible.map(\.id))
        return snapshot.index.ids.enumerated().map { (filtersActive ? allowed.contains($1) : true) && (placed?[$0] ?? true) }
    }
}

/// Thread-safe cancellation flag shared with background work.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}
