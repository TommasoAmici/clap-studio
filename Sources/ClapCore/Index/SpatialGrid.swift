import Foundation
import simd

/// Uniform grid over 2D points for hover hit-testing at 50k+ dots (constant-time lookups).
public struct SpatialGrid: Sendable {
    public let count: Int
    public let minX: Float, minY: Float, maxX: Float, maxY: Float
    private let cellsPerAxis: Int
    private let cellSize: Float
    private let cellStart: [Int32]
    private let items: [Int32]
    private let xy: [Float]

    public init(xy: [Float]) {
        let n = xy.count / 2
        count = n
        self.xy = xy
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for i in 0..<n {
            lo = simd_min(lo, SIMD2(xy[i * 2], xy[i * 2 + 1]))
            hi = simd_max(hi, SIMD2(xy[i * 2], xy[i * 2 + 1]))
        }
        if n == 0 { lo = .zero; hi = .zero }
        minX = lo.x; minY = lo.y; maxX = hi.x; maxY = hi.y

        let side = max(hi.x - lo.x, hi.y - lo.y, 1e-6)
        let axis = max(1, min(512, Int((Float(n) / 2).squareRoot())))
        cellsPerAxis = axis
        cellSize = side / Float(axis) * 1.0001

        var counts = [Int32](repeating: 0, count: axis * axis + 1)
        var cellOf = [Int32](repeating: 0, count: n)
        for i in 0..<n {
            let cx = min(axis - 1, Int((xy[i * 2] - lo.x) / cellSize)), cy = min(axis - 1, Int((xy[i * 2 + 1] - lo.y) / cellSize))
            let c = Int32(cy * axis + cx)
            cellOf[i] = c; counts[Int(c) + 1] += 1
        }
        for c in 0..<(axis * axis) { counts[c + 1] += counts[c] }
        var fill = counts
        var placed = [Int32](repeating: 0, count: n)
        for i in 0..<n { let c = Int(cellOf[i]); placed[Int(fill[c])] = Int32(i); fill[c] += 1 }
        cellStart = counts
        items = placed
    }

    /// Nearest point within `radius` of `p`, or nil. `isIncluded` skips points (e.g. filtered-out ones).
    public func nearest(to p: SIMD2<Float>, within radius: Float, isIncluded: ((Int) -> Bool)? = nil) -> Int? {
        guard count > 0 else { return nil }
        let axis = cellsPerAxis
        let x0 = max(0, Int(floorf((p.x - radius - minX) / cellSize))), x1 = min(axis - 1, Int(floorf((p.x + radius - minX) / cellSize)))
        let y0 = max(0, Int(floorf((p.y - radius - minY) / cellSize))), y1 = min(axis - 1, Int(floorf((p.y + radius - minY) / cellSize)))
        guard x0 <= x1, y0 <= y1 else { return nil }
        var best: Int?
        var bestD = radius * radius
        for cy in y0...y1 {
            for cx in x0...x1 {
                let c = cy * axis + cx
                for k in Int(cellStart[c])..<Int(cellStart[c + 1]) {
                    let i = Int(items[k])
                    if let isIncluded, !isIncluded(i) { continue }
                    let dx = xy[i * 2] - p.x, dy = xy[i * 2 + 1] - p.y
                    let d = dx * dx + dy * dy
                    if d <= bestD { bestD = d; best = i }
                }
            }
        }
        return best
    }

    /// Rows whose point lies inside the closed polygon `outline` (a lasso). `isIncluded` skips filtered-out points.
    public func rows(inPolygon outline: [SIMD2<Float>], isIncluded: ((Int) -> Bool)? = nil) -> [Int] {
        guard outline.count >= 3, count > 0 else { return [] }
        var lo = outline[0], hi = outline[0]
        for p in outline { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let axis = cellsPerAxis
        let x0 = max(0, Int(floorf((lo.x - minX) / cellSize))), x1 = min(axis - 1, Int(floorf((hi.x - minX) / cellSize)))
        let y0 = max(0, Int(floorf((lo.y - minY) / cellSize))), y1 = min(axis - 1, Int(floorf((hi.y - minY) / cellSize)))
        guard x0 <= x1, y0 <= y1 else { return [] }
        var found: [Int] = []
        for cy in y0...y1 {
            for cx in x0...x1 {
                let c = cy * axis + cx
                for k in Int(cellStart[c])..<Int(cellStart[c + 1]) {
                    let i = Int(items[k])
                    if let isIncluded, !isIncluded(i) { continue }
                    let p = SIMD2(xy[i * 2], xy[i * 2 + 1])
                    if p.x >= lo.x, p.x <= hi.x, p.y >= lo.y, p.y <= hi.y, Self.contains(outline, p) { found.append(i) }
                }
            }
        }
        return found.sorted()
    }

    /// Even-odd ray casting.
    static func contains(_ polygon: [SIMD2<Float>], _ p: SIMD2<Float>) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
