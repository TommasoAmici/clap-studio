import AppKit
import SwiftUI

/// Map colours that follow the system appearance: a dark canvas in dark mode, a light one in light mode.
enum MapTheme {
    static let darkBackground = NSColor(srgbRed: 0.07, green: 0.075, blue: 0.09, alpha: 1)
    static let lightBackground = NSColor(srgbRed: 0.955, green: 0.958, blue: 0.968, alpha: 1)

    static func isLight(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    static func background(light: Bool) -> NSColor { light ? lightBackground : darkBackground }

    /// For SwiftUI areas drawn next to the map (resolves with the view's appearance).
    static var backgroundColor: Color {
        Color(nsColor: NSColor(name: nil) { isLight($0) ? lightBackground : darkBackground })
    }

    /// Dot colours made for a dark canvas look washed out on a light one, so they are deepened:
    /// a little darker and a little more saturated. Greys stay grey.
    static func forLightBackground(_ c: SIMD4<Float>) -> SIMD4<Float> {
        let color = NSColor(deviceRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let deep = NSColor(deviceHue: h, saturation: min(1, s * 1.2), brightness: b * 0.8, alpha: 1)
        return SIMD4(Float(deep.redComponent), Float(deep.greenComponent), Float(deep.blueComponent), c.w)
    }
}
