import Foundation

/// A mounted USB stick (or other external drive) that could hold Squid banks.
public struct UsbDrive: Identifiable, Equatable, Sendable {
    public let url: URL
    public let name: String
    public let formatDescription: String
    public let capacity: Int64?
    public let available: Int64?
    public var id: String { url.path }

    public init(url: URL, name: String, formatDescription: String, capacity: Int64?, available: Int64?) {
        self.url = url; self.name = name; self.formatDescription = formatDescription
        self.capacity = capacity; self.available = available
    }

    public var isFAT32: Bool {
        let f = formatDescription.uppercased()
        return f.contains("FAT32") || (f.contains("FAT") && !f.contains("EXFAT") && !f.contains("FAT16") && !f.contains("FAT12"))
    }

    /// Whether a mounted volume looks like something a person plugged in: local, not the system disk.
    public static func isExternal(path: String, isInternal: Bool?, isRemovable: Bool?, isEjectable: Bool?, isLocal: Bool?) -> Bool {
        guard path.hasPrefix("/Volumes/"), path != "/Volumes/" else { return false }
        if isLocal == false { return false }
        if isInternal == true && isRemovable != true { return false }
        return isRemovable == true || isEjectable == true || isInternal == false
    }

    public static func current(fileManager fm: FileManager = .default) -> [UsbDrive] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey,
                                      .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  isExternal(path: url.path, isInternal: v.volumeIsInternal, isRemovable: v.volumeIsRemovable,
                             isEjectable: v.volumeIsEjectable, isLocal: v.volumeIsLocal) else { return nil }
            return UsbDrive(url: url, name: v.volumeName ?? url.lastPathComponent, formatDescription: v.volumeLocalizedFormatDescription ?? "",
                            capacity: v.volumeTotalCapacity.map(Int64.init), available: v.volumeAvailableCapacity.map(Int64.init))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
