#!/usr/bin/env swift
// Render the website's share image from the app icon and a real sound-map screenshot.
// Usage: swift scripts/render-og-image.swift [output.png] [map-light.png]
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.dropFirst().first ?? root.appendingPathComponent("website/og-image.png").path
let mapPath = CommandLine.arguments.dropFirst(2).first ?? root.appendingPathComponent("media/map-light.png").path
let width = 1200, height = 630
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
defer { NSGraphicsContext.restoreGraphicsState() }
let context = graphics.cgContext
let ink = NSColor(calibratedRed: 0.098, green: 0.106, blue: 0.090, alpha: 1)
let yellow = NSColor(calibratedRed: 0.933, green: 0.914, blue: 0.357, alpha: 1)
let pink = NSColor(calibratedRed: 0.925, green: 0.322, blue: 0.725, alpha: 1)

func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(height) - top - h, width: w, height: h)
}

func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat,
          color: NSColor = ink, display: Bool = false) {
    let font = display ? NSFont(name: "Impact", size: size)! : NSFont.systemFont(ofSize: size, weight: .bold)
    (value as NSString).draw(at: CGPoint(x: x, y: CGFloat(height) - top - font.ascender),
                             withAttributes: [.font: font, .foregroundColor: color])
}

func image(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Cannot read \(path). Download the screenshots with Git LFS before rendering.")
    }
    return cg
}

context.setFillColor(yellow.cgColor)
context.fill(rect(0, 0, 1200, 630))
context.interpolationQuality = .high
context.draw(image(root.appendingPathComponent("clap.icon/readme.png").path), in: rect(48, 32, 90, 90))
text("CLAP STUDIO", x: 151, top: 57, size: 30)
text("A SAMPLE EXPLORER FOR macOS", x: 61, top: 133, size: 16)
text("LESS SEARCH.", x: 57, top: 184, size: 92, display: true)
text("MORE SOUND.", x: 62, top: 290, size: 92, color: pink, display: true)
text("MORE SOUND.", x: 57, top: 285, size: 92, display: true)
text("Find your next sound.", x: 61, top: 408, size: 26)
text("Make something new.", x: 61, top: 447, size: 26)

let screenshot = rect(664, 179, 480, 300)
context.saveGState()
context.setShadow(offset: CGSize(width: 9, height: -12), blur: 0, color: pink.cgColor)
context.setFillColor(ink.cgColor)
context.addPath(CGPath(roundedRect: screenshot.insetBy(dx: -2, dy: -2),
                       cornerWidth: 13, cornerHeight: 13, transform: nil))
context.fillPath()
context.restoreGState()
context.saveGState()
context.addPath(CGPath(roundedRect: screenshot, cornerWidth: 11, cornerHeight: 11, transform: nil))
context.clip()
context.draw(image(mapPath), in: screenshot)
context.restoreGState()
text("YOUR WHOLE LIBRARY. A FRESH WAY IN.", x: 671, top: 506, size: 14)

context.setFillColor(ink.cgColor)
context.fill(rect(0, 562, 1200, 68))
text("SEARCH BY SOUND    /    MAKE BEATS    /    SQUID SALMPLE",
     x: 61, top: 586, size: 20, color: yellow)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Rendered \(output) (\(width) × \(height))")
