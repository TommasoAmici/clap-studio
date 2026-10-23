import Foundation

/// Irregular demonstration clouds keep related sounds nearby without arranging them in rings.
enum MediaLayout {
    static func point(family: Int, variation: Int) -> (Float, Float) {
        let centers: [(Double, Double)] = [(-0.66, -0.26), (-0.28, -0.44), (-0.55, 0.22),
            (-0.06, -0.04), (0.03, 0.52), (0.37, 0.03), (0.58, 0.37), (0.52, -0.39)]
        var state = UInt64(family * 1000 + variation + 2026)
        func unit() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return (Double(state >> 32) + 0.5) / (Double(UInt32.max) + 1)
        }
        let distance = sqrt(-2 * log(unit()))
        let theta = unit() * 2 * .pi
        let a = distance * cos(theta) * (0.09 + Double(family % 3) * 0.025)
        let b = distance * sin(theta) * 0.075
        let rotation = Double(family) * 0.83
        var center = centers[family]
        // A few sounds fall between families, like the overlaps in a learned sound map.
        if variation % 7 == 0 {
            let next = centers[(family + 1) % centers.count]
            let blend = unit() * 0.6
            center = (center.0 * (1 - blend) + next.0 * blend,
                      center.1 * (1 - blend) + next.1 * blend)
        }
        return (Float(center.0 + a * cos(rotation) - b * sin(rotation)),
                Float(center.1 + a * sin(rotation) + b * cos(rotation)))
    }
}
