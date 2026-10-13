import Foundation

/// Recordings made at (nearly) the same place, shown as one pin on a map.
public struct PlaceCluster: Identifiable, Equatable, Sendable {
    public let id: String
    /// The middle of the recordings.
    public let center: GeoPoint
    public let ids: [Int64]
    public var count: Int { ids.count }
}

public enum PlaceGrouping {
    /// Starting size of a pin's cell in degrees (about a kilometre).
    public static let baseCell = 0.01

    /// Joins recordings that are within a cell's width of a pin, making the cells bigger until there are no more than
    /// `maxPins`, so a whole world of recordings stays drawable. Biggest groups first.
    public static func group(_ located: [(id: Int64, point: GeoPoint)], maxPins: Int = 400) -> [PlaceCluster] {
        guard !located.isEmpty else { return [] }
        var radius = baseCell
        var clusters = merge(located, radius: radius)
        while clusters.count > maxPins && radius < 90 {
            radius *= 2.5
            clusters = merge(located, radius: radius)
        }
        return clusters.map { cluster in
            let ids = cluster.members.map(\.id).sorted()
            return PlaceCluster(id: "p\(ids[0])", center: GeoPoint(latitude: cluster.lat, longitude: cluster.lon) ?? cluster.members[0].point, ids: ids)
        }.sorted { ($0.count, $1.id) > ($1.count, $0.id) }
    }

    private struct Cell: Hashable { let row: Int, column: Int }

    private struct Building {
        var lat: Double, lon: Double
        var members: [(id: Int64, point: GeoPoint)]
    }

    /// A pin takes a recording when it is within `radius` degrees (east-west distances shrink towards the poles).
    /// Pins are found through a grid of the same size, so this stays fast for a large library.
    private static func merge(_ located: [(id: Int64, point: GeoPoint)], radius: Double) -> [Building] {
        var pins: [Building] = []
        var grid: [Cell: [Int]] = [:]
        func cell(_ lat: Double, _ lon: Double) -> Cell { Cell(row: Int((lat / radius).rounded(.down)), column: Int((lon / radius).rounded(.down))) }
        for item in located.sorted(by: { $0.id < $1.id }) {
            let home = cell(item.point.latitude, item.point.longitude)
            let scale = max(0.05, cos(item.point.latitude * .pi / 180))
            var target: Int?
            search: for dr in -1...1 {
                for dc in -1...1 {
                    for index in grid[Cell(row: home.row + dr, column: home.column + dc)] ?? [] {
                        let dLat = pins[index].lat - item.point.latitude
                        let dLon = (pins[index].lon - item.point.longitude) * scale
                        if dLat * dLat + dLon * dLon <= radius * radius { target = index; break search }
                    }
                }
            }
            if let target {
                let n = Double(pins[target].members.count)
                pins[target].lat = (pins[target].lat * n + item.point.latitude) / (n + 1)
                pins[target].lon = (pins[target].lon * n + item.point.longitude) / (n + 1)
                pins[target].members.append(item)
            } else {
                grid[home, default: []].append(pins.count)
                pins.append(Building(lat: item.point.latitude, lon: item.point.longitude, members: [item]))
            }
        }
        return pins
    }
}
