import AppKit
import ClapCore
import Foundation

/// A place on a USB stick that is selected in the sidebar.
struct UsbSelection: Hashable {
    enum Area: Hashable { case set(String?), bank(set: String?, number: Int), pool, poolFolder([String]) }
    let drive: String          // UsbDrive.id
    let area: Area

    private static let separator = "\u{1F}"
    private static let bankSeparator = "\u{1E}"      // between a bank's number and its set's name

    var tag: String {
        switch area {
        case .pool: return ["usb", "pool", "", drive].joined(separator: Self.separator)
        case .poolFolder(let path): return ["usb", "poolfolder", path.joined(separator: "/"), drive].joined(separator: Self.separator)
        case .set(let name): return ["usb", "set", name ?? "", drive].joined(separator: Self.separator)
        case .bank(let set, let number): return ["usb", "bank", "\(number)\(Self.bankSeparator)\(set ?? "")", drive].joined(separator: Self.separator)
        }
    }

    init(drive: String, area: Area) { self.drive = drive; self.area = area }

    init?(tag: String) {
        let parts = tag.split(separator: Character(Self.separator), maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "usb" else { return nil }
        self.drive = parts[3]
        switch parts[1] {
        case "pool": self.area = .pool
        case "poolfolder":
            let path = parts[2].split(separator: "/").map(String.init)      // a folder name cannot hold "/"
            guard !path.isEmpty else { return nil }
            self.area = .poolFolder(path)
        case "set": self.area = .set(parts[2].isEmpty ? nil : parts[2])
        case "bank":
            let pieces = parts[2].split(separator: Character(Self.bankSeparator), maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard pieces.count == 2, let number = Int(pieces[0]) else { return nil }
            self.area = .bank(set: pieces[1].isEmpty ? nil : pieces[1], number: number)
        default: return nil
        }
    }
}

/// Where the export sheet starts: which drive, which set, which bank (to add to), and whether the Pool is meant.
struct SquidTarget {
    var drive: String?
    var set: String?
    var pool = false
    var bank: Int?
    var poolFolder = ""
}

/// A sample or folder in the Pool of a stick: the drive and the path from the Pool down.
struct PoolEntry: Sendable, Equatable {
    let drive: String
    let path: [String]
}

/// A name being edited in place, Finder style.
enum UsbRename: Equatable {
    case set(drive: String, name: String)
    case bank(drive: String, set: String?, number: Int)
}

/// Squid Salmple support: USB sticks in the sidebar, their banks and Pool browsable and analysed, and export to them.
/// There is no setting: a connected drive with an `ALM022` folder switches it on, and unplugging the last one switches it off.
extension AppModel {
    // MARK: drives

    /// Starts listening for sticks being plugged in, renamed or removed.
    func watchUsbDrives() {
        guard usbObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            usbObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshUsbDrives() }
            })
        }
        // Edits made in Finder while the app was in the background show up when it comes back.
        usbObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                                   queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUsbDrives(settle: false) }
        })
        refreshUsbDrives(settle: false)
    }

    /// A place on a stick is showing, in place of the library list or the map.
    var showingUsb: Bool { usbSelection != nil && squidEnabled }

    /// Chooses the library list or the map. From a stick's banks it leaves the stick, for all samples.
    func show(_ mode: ViewMode) {
        viewMode = mode
        if showingUsb { selectSidebar("smart.\(SmartFilter.all.rawValue)") }
    }

    /// Looks at the connected drives again (after a short pause, so a stick that just mounted can finish).
    func refreshUsbDrives(settle: Bool = true) {
        usbRefreshTask?.cancel()
        usbRefreshTask = Task {
            if settle { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            let found = await Task.detached { () -> ([UsbDrive], [String: SquidStickContents]) in
                // Only a drive with an ALM022 folder is one for the module; any other stick is left alone.
                let drives = UsbDrive.current().filter { SquidStick.isForModule(volume: $0.url) }
                return (drives, Dictionary(uniqueKeysWithValues: drives.map { ($0.id, SquidStick.read(volume: $0.url)) }))
            }.value
            guard !Task.isCancelled else { return }
            if found.0 != usbDrives { usbDrives = found.0 }
            usbContents = found.1
            syncUsbRoots()
        }
    }

    /// Each stick's ALM022 folder becomes a temporary library root, so its samples are read and analysed
    /// like any folder but never saved as part of the library.
    private func syncUsbRoots() {
        guard let store else { return }
        let wanted = usbDrives.map { SquidStick.rootURL(volume: $0.url).path }
        for root in store.transientRoots() where !wanted.contains(root.path) { try? store.removeRoot(id: root.id) }
        for path in wanted { _ = try? store.addRoot(path: path, transient: true) }
        if let selection = usbSelection, !isAvailable(selection) {
            // A bank that went away leaves its set open, if the set is still there.
            if case .bank(let set, _) = selection.area, usbContents[selection.drive]?.set(named: set) != nil {
                selectSidebar(UsbSelection(drive: selection.drive, area: .set(set)).tag)
            } else if case .poolFolder = selection.area, usbContents[selection.drive]?.hasPool == true {
                selectSidebar(UsbSelection(drive: selection.drive, area: .pool).tag)       // a folder that went away leaves the Pool open
            } else {
                selectSidebar("smart.\(SmartFilter.all.rawValue)")
            }
        }
        reloadSamples()
        if !wanted.isEmpty { requestIndexing() }
    }

    private func isAvailable(_ selection: UsbSelection) -> Bool {
        guard let contents = usbContents[selection.drive], usbDrives.contains(where: { $0.id == selection.drive }) else { return false }
        switch selection.area {
        case .pool: return contents.hasPool
        case .poolFolder(let path): return contents.poolFolder(at: path) != nil
        case .set(let name): return contents.set(named: name) != nil
        case .bank(let set, let number): return contents.set(named: set)?.banks.contains { $0.number == number } ?? false
        }
    }

    /// Indexes now, or as soon as the running index finishes.
    func requestIndexing() {
        if isIndexing { usbIndexQueued = true } else { startIndexing() }
    }

    func ejectUsb(_ drive: UsbDrive) {
        do { try NSWorkspace.shared.unmountAndEjectDevice(at: drive.url) }
        catch { errorMessage = "Could not eject \(drive.name): \(error.localizedDescription)" }
    }

    func drive(id: String) -> UsbDrive? { usbDrives.first { $0.id == id } }

    /// Looks at the sticks again and waits for it.
    func reloadUsb() async {
        refreshUsbDrives(settle: false)
        await usbRefreshTask?.value
    }

    // MARK: samples

    /// The stick's samples that belong to a sidebar selection (one set or the Pool).
    func usbSamples(in selection: UsbSelection) -> [SampleRecord] {
        guard let drive = drive(id: selection.drive) else { return [] }
        let root = SquidStick.rootURL(volume: drive.url).path
        return usbSamples.filter { sample in
            guard sample.rootPath == root else { return false }
            let location = SquidLayout.location(ofRelativePath: sample.relPath)
            switch (location, selection.area) {
            case (.bank(let set, _, _), .set(let wanted)): return SquidLayout.sameSet(set, wanted)
            case (.bank(let set, let number, _), .bank(let wantedSet, let wantedNumber)):
                return number == wantedNumber && SquidLayout.sameSet(set, wantedSet)
            case (_, .pool): return SquidLayout.location(location, isInPoolFolder: [])
            case (_, .poolFolder(let path)): return SquidLayout.location(location, isInPoolFolder: path)
            default: return false
            }
        }
    }

    /// Files on a stick are never written to (not even to store cues in them).
    func isOnUsb(_ id: Int64) -> Bool { usbSampleIDs.contains(id) }

    /// Replaces the drum machine's sounds with a bank's samples.
    func loadBankIntoDrums(_ samples: [SampleRecord]) {
        drumMachine.stop()
        drumPattern = DrumPattern(swing: drumPattern.swing)
        addToDrums(samples.map(\.id))
    }
}
