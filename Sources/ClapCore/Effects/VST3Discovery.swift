import Foundation

/// Finds installed VST3 bundles without loading any plugin code.
public enum VST3Discovery {
    public static var defaultLocations: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Audio/Plug-Ins/VST3"),
         URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3")]
    }

    public static func bundles(in locations: [URL] = defaultLocations) -> [URL] {
        var found = Set<URL>()
        for location in locations {
            guard let entries = FileManager.default.enumerator(at: location, includingPropertiesForKeys: [.isDirectoryKey],
                                                               options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in entries where url.pathExtension.lowercased() == "vst3" {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                found.insert(url.standardizedFileURL)
                entries.skipDescendants()
            }
        }
        return found.sorted {
            let order = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }
}
