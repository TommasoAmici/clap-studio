import AppKit
import ClapCore
import Foundation

enum MapColorMode: String, CaseIterable, Identifiable {
    case cluster = "Cluster", category = "Category", kind = "Loop or one-shot", usage = "Usage"
    case tempo = "Tempo", loudness = "Loudness", brightness = "Brightness"
    var id: String { rawValue }

    var property: MapProperty? {
        switch self {
        case .tempo: return .tempo
        case .loudness: return .loudness
        case .brightness: return .brightness
        default: return nil
        }
    }
}

/// What colours the dots: an index into the 24-colour palette per map row, the palette itself, and a legend.
struct MapColoring {
    struct Entry: Identifiable { let id: Int; let label: String; let count: Int }
    var indices: [UInt8]
    var palette: [NSColor]
    var legend: [Entry]                 // categorical modes
    var gradient: (low: String, high: String)?   // continuous modes

    static let unknown = 23

    @MainActor
    static func make(mode: MapColorMode, snapshot: AnalysisSnapshot, samples: [Int64: SampleRecord]) -> MapColoring? {
        let ids = snapshot.index.ids
        switch mode {
        case .cluster:
            return nil            // the renderer's own cluster colours
        case .category:
            let names = SoundCategories.names
            var counts = [Int](repeating: 0, count: names.count)
            let indices = ids.map { id -> UInt8 in
                guard let name = samples[id]?.effectiveCategory, let i = names.firstIndex(of: name) else { return UInt8(unknown) }
                counts[i] += 1
                return UInt8(i)
            }
            return MapColoring(indices: indices, palette: (0..<24).map { $0 == unknown ? .gray : Palette.color($0) },
                               legend: names.indices.filter { counts[$0] > 0 }.map { Entry(id: $0, label: names[$0], count: counts[$0]) },
                               gradient: nil)
        case .kind:
            var counts = [0, 0, 0, 0]
            let indices = ids.map { id -> UInt8 in
                if samples[id]?.isFieldRecording == true { counts[2] += 1; return 2 }
                switch samples[id]?.isLoop {
                case true?: counts[0] += 1; return 0
                case false?: counts[1] += 1; return 1
                default: counts[3] += 1; return UInt8(unknown)
                }
            }
            return MapColoring(indices: indices, palette: (0..<24).map { $0 == 0 ? Palette.color(0) : ($0 == 1 ? Palette.color(3) : ($0 == 2 ? Palette.color(6) : .gray)) },
                               legend: [Entry(id: 0, label: "Loops", count: counts[0]), Entry(id: 1, label: "One-shots", count: counts[1]),
                                        Entry(id: 2, label: "Field recordings", count: counts[2]),
                                        Entry(id: unknown, label: "Not measured", count: counts[3])].filter { $0.count > 0 },
                               gradient: nil)
        case .usage:
            var counts = [0, 0]
            let indices = ids.map { id -> UInt8 in
                let used = (samples[id]?.useCount ?? 0) > 0
                counts[used ? 1 : 0] += 1
                return used ? 1 : 0
            }
            return MapColoring(indices: indices, palette: (0..<24).map { $0 == 1 ? NSColor.orange : NSColor(white: 0.55, alpha: 1) },
                               legend: [Entry(id: 1, label: "Used", count: counts[1]), Entry(id: 0, label: "Never used", count: counts[0])],
                               gradient: nil)
        case .tempo, .loudness, .brightness:
            guard let property = mode.property else { return nil }
            let values = ids.map { samples[$0].flatMap(property.value) }
            let present = values.compactMap { $0 }.sorted()
            guard present.count > 1 else { return nil }
            // Trim the extremes so a few outliers do not wash out the gradient.
            let low = present[Int(Double(present.count - 1) * 0.02)], high = present[Int(Double(present.count - 1) * 0.98)]
            let bins = 22
            let indices = values.map { v -> UInt8 in v.map { UInt8(MapAxes.bin($0, low: low, high: high, bins: bins)) } ?? UInt8(unknown) }
            let palette = (0..<24).map { i -> NSColor in
                i >= bins ? .gray : NSColor(hue: 0.68 * (1 - CGFloat(i) / CGFloat(bins - 1)), saturation: 0.8, brightness: 0.95, alpha: 1)
            }
            let label: (Double) -> String = { v in
                switch property {
                case .tempo: return String(format: "%.0f BPM", v)
                case .loudness: return String(format: "%.0f dB", v)
                default: return String(format: "%.0f Hz", pow(2, v))
                }
            }
            return MapColoring(indices: indices, palette: palette, legend: [], gradient: (label(low), label(high)))
        }
    }
}

extension AppModel {
    /// Recomputes dot colours for the current mode (nil mode data means the plain cluster colours).
    func refreshMapColoring() {
        if mapColorMode == .cluster || snapshot == nil { mapColoring = nil }
        else if let snapshot { mapColoring = MapColoring.make(mode: mapColorMode, snapshot: snapshot, samples: sampleByID) }
        mapColorVersion += 1
    }

    /// Lays the map out by two measured properties instead of by similarity (nil goes back to similarity).
    func refreshMapLayout() {
        if let axes = mapAxes, let snapshot {
            axisLayout = MapAxes.layout(snapshot.index.ids.map { sampleByID[$0] }, x: axes.x, y: axes.y)
        } else {
            axisLayout = nil
        }
        mapVersion += 1
        filterVersion += 1
    }

    func selectOnMap(rows: [Int]) {
        guard let snapshot else { return }
        mapSelection = rows.map { snapshot.index.ids[$0] }
    }

    func clearMapSelection() { mapSelection = [] }
}
