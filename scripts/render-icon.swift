#!/usr/bin/env swift
// Renders clap.icon (Icon Composer) to an .iconset folder without Xcode.
//   swift scripts/render-icon.swift clap.icon build/AppIcon.iconset
// With Icon Composer installed (its `ictool`, or ICTOOL=/path/to/ictool) the artwork is rendered by Apple's own
// renderer, Liquid Glass included. Without it a flat approximation is drawn: gradient background, tinted layers
// and offsets are honoured, but only for PNG layers with a plain `position`, and no glass lighting.
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: render-icon.swift <name.icon> <out.iconset>"); exit(2) }
let iconDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
let spec = try JSONSerialization.jsonObject(with: Data(contentsOf: iconDir.appendingPathComponent("icon.json"))) as! [String: Any]

func color(_ s: String) -> CGColor {
    // "extended-srgb:r,g,b,a" or "extended-gray:w,a"
    let parts = s.split(separator: ":"), v = parts[1].split(separator: ",").compactMap { Double($0) }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    if parts[0].contains("gray") { return CGColor(colorSpace: cs, components: [v[0], v[0], v[0], v[1]])! }
    return CGColor(colorSpace: cs, components: v.map { CGFloat($0) })!
}

func rgb(_ c: CGColor) -> [CGFloat] { c.components ?? [0, 0, 0, 1] }
func mix(_ a: CGColor, _ b: [CGFloat], _ t: CGFloat) -> CGColor {
    let x = rgb(a)
    return CGColor(red: x[0] + (b[0] - x[0]) * t, green: x[1] + (b[1] - x[1]) * t, blue: x[2] + (b[2] - x[2]) * t, alpha: 1)
}

/// Alpha-only copy of an image, usable as a clipping mask.
func alphaMask(_ image: CGImage) -> CGImage {
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

/// Apple's ictool, when Icon Composer (or Xcode) is installed.
let ictool: String? = {
    let env = ProcessInfo.processInfo.environment["ICTOOL"]
    let candidates = [env, "/Applications/Icon Composer.app/Contents/Executables/ictool",
                      "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"].compactMap { $0 }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}()

/// The icon artwork (the full-bleed squircle) rendered by ictool at `pixels` square, or nil when that is not possible.
func renderWithIconComposer(pixels: Int) -> CGImage? {
    guard let ictool else { return nil }
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("clap-icon-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: out) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ictool)
    process.arguments = [iconDir.path, "--export-image", "--output-file", out.path, "--platform", "macOS", "--rendition", "Default",
                         "--width", "\(pixels)", "--height", "\(pixels)", "--scale", "1"]
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    guard process.terminationStatus == 0, let image = NSImage(contentsOf: out),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width == pixels else { return nil }
    return cg
}

func render(size: Int) -> Data {
    // macOS icon grid: the artwork is an 824/1024 squircle centred in the canvas, with a soft shadow below it.
    let artSize = Int((Double(size) * 824 / 1024).rounded())
    if let art = renderWithIconComposer(pixels: artSize) {
        let S = CGFloat(size), cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.009), blur: S * 0.02, color: CGColor(gray: 0, alpha: 0.35))
        let origin = CGFloat(size - artSize) / 2
        ctx.draw(art, in: CGRect(x: origin, y: origin, width: CGFloat(artSize), height: CGFloat(artSize)))
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }
    return renderApproximation(size: size)
}

func renderApproximation(size: Int) -> Data {
    let S = CGFloat(size), cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    // macOS icon grid: the artwork is an 824/1024 squircle centred in the canvas.
    let art = S * 824 / 1024, origin = (S - art) / 2, k = art / 1024     // k: icon-canvas points -> pixels
    let tile = CGRect(x: origin, y: origin, width: art, height: art)
    let shape = CGPath(roundedRect: tile, cornerWidth: art * 0.225, cornerHeight: art * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.009), blur: S * 0.02, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let base = color(((spec["fill"] as? [String: String])?["automatic-gradient"]) ?? "extended-gray:0.5,1")
    let gradient = CGGradient(colorsSpace: cs, colors: [mix(base, [1, 1, 1], 0.28), base] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    // icon.json lists layers front to back, so paint in reverse.
    let layers = ((spec["groups"] as! [[String: Any]]).flatMap { $0["layers"] as! [[String: Any]] }).reversed()
    for layer in layers {
        let url = iconDir.appendingPathComponent("Assets/\(layer["image-name"] as! String)")
        guard let src = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        let t = ((layer["position"] as? [String: Any])?["translation-in-points"] as? [Double]) ?? [0, 0]
        let w = CGFloat(src.width) * k, h = CGFloat(src.height) * k
        let rect = CGRect(x: tile.midX - w / 2 + CGFloat(t[0]) * k, y: tile.midY - h / 2 - CGFloat(t[1]) * k, width: w, height: h)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.006), blur: S * 0.012, color: CGColor(gray: 0, alpha: 0.25))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.clip(to: rect, mask: alphaMask(src))
        let fill = layer["fill"] as? [String: Any]
        if let stops = fill?["linear-gradient"] as? [String] {
            let o = fill?["orientation"] as? [String: [String: Double]]
            let a = o?["start"] ?? ["x": 0.5, "y": 0], b = o?["stop"] ?? ["x": 0.5, "y": 1]
            func point(_ p: [String: Double]) -> CGPoint {   // orientation is relative to the layer, y down
                CGPoint(x: rect.minX + rect.width * p["x"]!, y: rect.maxY - rect.height * p["y"]!)
            }
            let g = CGGradient(colorsSpace: cs, colors: stops.map(color) as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: point(a), end: point(b), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        } else {
            ctx.setFillColor(color((fill?["solid"] as? String) ?? "extended-gray:1,1"))
            ctx.fill(rect)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

if ictool == nil {
    FileHandle.standardError.write(Data("warning: Icon Composer (ictool) not found; drawing a flat approximation that ignores newer icon features (SVG layers, gradients, opacity, glass). Install Icon Composer or set ICTOOL.\n".utf8))
}
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Rendered \(outDir.path)")
