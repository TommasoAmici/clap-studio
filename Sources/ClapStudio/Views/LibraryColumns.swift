import ClapCore
import Foundation

/// How a column sorts: by text (the way Finder orders names, "kick 2" before "kick 10") or by number.
enum LibrarySortKey {
    case text((SampleRecord) -> String)
    case number((SampleRecord) -> Double)
}

/// One column of the library list: what it shows, how it sorts and how wide it starts out. The list view and
/// the sorting code both read this table, so a column cannot show one thing and sort by another.
struct LibraryColumn {
    let id: String
    let title: String
    let width: CGFloat
    let minWidth: CGFloat
    var hiddenByDefault = false
    var monospacedDigits = false
    var truncatesHead = false
    /// What the cell shows (the name and uses columns draw their own cells and use this for nothing else).
    let text: (SampleRecord) -> String
    let sortKey: LibrarySortKey
    let keyPath: PartialKeyPath<SampleRecord>
    let comparator: (SortOrder) -> KeyPathComparator<SampleRecord>

    static let name = "name"
    static let uses = "uses"

    private static func textColumn(_ id: String, _ title: String, _ keyPath: KeyPath<SampleRecord, String>,
                                   width: CGFloat, minWidth: CGFloat? = nil, show: ((SampleRecord) -> String)? = nil,
                                   hidden: Bool = false, headTruncation: Bool = false) -> LibraryColumn {
        LibraryColumn(id: id, title: title, width: width, minWidth: minWidth ?? width, hiddenByDefault: hidden,
                      truncatesHead: headTruncation,
                      text: show ?? { $0[keyPath: keyPath] },
                      sortKey: .text { $0[keyPath: keyPath] },
                      keyPath: keyPath,
                      comparator: { KeyPathComparator(keyPath, comparator: .localizedStandard, order: $0) })
    }

    private static func numberColumn<Value: Comparable>(_ id: String, _ title: String, _ keyPath: KeyPath<SampleRecord, Value>,
                                                        width: CGFloat, minWidth: CGFloat? = nil, hidden: Bool = false,
                                                        digits: Bool = false, asDouble: @escaping (Value) -> Double,
                                                        show: @escaping (SampleRecord) -> String) -> LibraryColumn {
        LibraryColumn(id: id, title: title, width: width, minWidth: minWidth ?? width, hiddenByDefault: hidden,
                      monospacedDigits: digits, text: show,
                      sortKey: .number { asDouble($0[keyPath: keyPath]) },
                      keyPath: keyPath,
                      comparator: { KeyPathComparator(keyPath, order: $0) })
    }

    static let all: [LibraryColumn] = [
        textColumn(name, "Name", \.name, width: 260, minWidth: 180),
        numberColumn("length", "Length", \.duration, width: 60, digits: true, asDouble: { $0 }) { Format.duration($0.duration) },
        numberColumn("bpm", "BPM", \.bpmSort, width: 52, digits: true, asDouble: { $0 }) { $0.bpmText },
        textColumn("key", "Key", \.keySort, width: 72, minWidth: 40, show: { $0.keyName ?? "" }),
        numberColumn("level", "Level", \.levelSort, width: 62, digits: true, asDouble: { $0 }) { $0.levelText },
        numberColumn("bright", "Bright", \.brightnessSort, width: 64, digits: true, asDouble: { $0 }) { $0.brightnessText },
        textColumn("category", "Category", \.categorySort, width: 90, minWidth: 60, show: { $0.effectiveCategory ?? "" }),
        textColumn("mood", "Mood", \.moodText, width: 110, minWidth: 60),
        numberColumn("cues", "Cues", \.cueCount, width: 44, digits: true, asDouble: { Double($0) }) { $0.cueCount == 0 ? "" : "\($0.cueCount)" },
        numberColumn(uses, "Uses", \.useCount, width: 56, asDouble: { Double($0) }) { $0.useCount == 0 ? "–" : "\($0.useCount)×" },
        textColumn("tags", "Tags", \.tagsText, width: 120, minWidth: 60, hidden: true),
        textColumn("folder", "Folder", \.folder, width: 140, minWidth: 60, hidden: true, headTruncation: true),
        textColumn("format", "Format", \.formatText, width: 52, hidden: true),
        numberColumn("rate", "Rate", \.sampleRate, width: 68, hidden: true, digits: true, asDouble: { $0 }) {
            $0.sampleRate > 0 ? String(format: "%g kHz", $0.sampleRate / 1000) : ""
        },
        numberColumn("channels", "Ch", \.channels, width: 52, hidden: true, asDouble: { Double($0) }) {
            $0.channels == 0 ? "" : $0.channels == 1 ? "Mono" : $0.channels == 2 ? "Stereo" : "\($0.channels) ch"
        },
        numberColumn("size", "Size", \.size, width: 68, hidden: true, digits: true, asDouble: { Double($0) }) {
            $0.size.formatted(.byteCount(style: .file))
        },
        numberColumn("modified", "Modified", \.mtime, width: 96, minWidth: 70, hidden: true, asDouble: { $0 }) {
            Date(timeIntervalSince1970: $0.mtime).formatted(date: .abbreviated, time: .omitted)
        },
    ]

    static func column(id: String) -> LibraryColumn? { all.first { $0.id == id } }
    static func column(for keyPath: PartialKeyPath<SampleRecord>) -> LibraryColumn? { all.first { $0.keyPath == keyPath } }
}

/// Sorts the library the way the list's headings ask. `Array.sort(using:)` with a `KeyPathComparator` re-derives
/// both values and runs the locale-aware string comparison on every step; at tens of thousands of samples that
/// is over a second. This computes each key once and compares plain values.
enum LibrarySort {
    static func sorted(_ list: [SampleRecord], by comparators: [KeyPathComparator<SampleRecord>]) -> [SampleRecord] {
        let columns = comparators.map { LibraryColumn.column(for: $0.keyPath) }
        guard list.count > 1, !comparators.isEmpty, !columns.contains(where: { $0 == nil }) else {
            return list.sorted(using: comparators)
        }
        enum Keys { case text([String]), number([Double]) }
        let keys: [Keys] = columns.map { column in
            switch column!.sortKey {
            case .text(let key): return .text(list.map(key))
            case .number(let key): return .number(list.map(key))
            }
        }
        let descending = comparators.map { $0.order == .reverse }
        var order = Array(list.indices)
        order.sort { a, b in
            for (level, key) in keys.enumerated() {
                switch key {
                case .text(let values):
                    let result = values[a].localizedStandardCompare(values[b])
                    if result != .orderedSame { return (result == .orderedAscending) != descending[level] }
                case .number(let values):
                    if values[a] != values[b] { return (values[a] < values[b]) != descending[level] }
                }
            }
            return a < b            // ties keep their previous order
        }
        return order.map { list[$0] }
    }
}
