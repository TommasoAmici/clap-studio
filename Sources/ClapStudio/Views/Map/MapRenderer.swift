import AppKit
import MetalKit
import simd

/// Distinct cluster colours (golden-angle hues, alternating saturation/brightness).
enum Palette {
    static let count = 24

    static func color(_ i: Int) -> NSColor {
        let hue = (Double(i) * 0.381966).truncatingRemainder(dividingBy: 1)
        let odd = i % 2 == 1
        return NSColor(hue: hue, saturation: odd ? 0.55 : 0.78, brightness: odd ? 0.98 : 0.92, alpha: 1)
    }

    static func simd(_ i: Int) -> SIMD4<Float> {
        let c = color(i).usingColorSpace(.deviceRGB) ?? .white
        return SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1)
    }
}

struct MapUniforms {
    var center = SIMD2<Float>(0, 0)
    var viewport = SIMD2<Float>(1, 1)
    var scale: Float = 1
    var pointSize: Float = 3
    var alpha: Float = 0.85
    var pad: Float = 0
}

struct HighlightEntry {
    var index: UInt32
    var kind: UInt32     // 1 similar, 2 selected, 3 hover
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms { float2 center; float2 viewport; float scale; float pointSize; float alpha; float pad; };
struct VOut { float4 position [[position]]; float size [[point_size]]; float4 color; float kind; };

vertex VOut vmain(uint vid [[vertex_id]],
                  const device float2* pos [[buffer(0)]],
                  const device uchar* cl [[buffer(1)]],
                  const device uchar* vis [[buffer(2)]],
                  constant Uniforms& u [[buffer(3)]],
                  constant float4* palette [[buffer(4)]]) {
    VOut o;
    float2 p = (pos[vid] - u.center) * u.scale * 2.0 / u.viewport;
    if (vis[vid] == 0) { p = float2(4.0, 4.0); }   // filtered out: move outside the clip volume
    o.position = float4(p, 0.0, 1.0);
    o.size = u.pointSize;
    float4 c = palette[cl[vid] % 24];
    c.a = u.alpha;
    o.color = c;
    o.kind = 0.0;
    return o;
}

vertex VOut vhigh(uint vid [[vertex_id]],
                  const device float2* pos [[buffer(0)]],
                  const device uchar* cl [[buffer(1)]],
                  constant Uniforms& u [[buffer(3)]],
                  constant float4* palette [[buffer(4)]],
                  const device uint2* hl [[buffer(5)]]) {
    VOut o;
    uint idx = hl[vid].x;
    uint kind = hl[vid].y;
    float2 p = (pos[idx] - u.center) * u.scale * 2.0 / u.viewport;
    o.position = float4(p, 0.0, 1.0);
    o.size = u.pointSize * (kind == 2 ? 2.8 : (kind == 3 ? 2.4 : 1.7));
    float4 c = palette[cl[idx] % 24];
    c.a = 1.0;
    o.color = c;
    o.kind = float(kind);
    return o;
}

fragment float4 fmain(VOut in [[stage_in]], float2 pc [[point_coord]]) {
    float r = length(pc - 0.5) * 2.0;
    if (r > 1.0) { discard_fragment(); }
    float4 c = in.color;
    if (in.kind >= 2.0 && r > 0.7) { c = float4(1.0, 1.0, 1.0, 1.0); }
    else if (in.kind >= 1.0 && r > 0.82) { c = float4(0.0, 0.0, 0.0, 0.7); }
    c.a *= smoothstep(1.0, 0.85, r);
    return c;
}
"""

/// Draws all dots as GPU point sprites (50k dots at 60 fps) plus a small highlight pass.
final class MapRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let normalPipeline: MTLRenderPipelineState
    private let highlightPipeline: MTLRenderPipelineState
    private var positions: MTLBuffer?
    private var clusters: MTLBuffer?
    private var visibility: MTLBuffer?
    private var highlights: MTLBuffer?
    private var highlightCount = 0
    private(set) var pointCount = 0
    private var palette = (0..<Palette.count).map(Palette.simd)

    /// Supplied by the owning view so the renderer always draws the latest transform.
    var uniformsProvider: () -> MapUniforms = { MapUniforms() }

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.07, green: 0.075, blue: 0.09, alpha: 1)
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else { return nil }
        func pipeline(_ vertex: String) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: "fmain")
            let a = d.colorAttachments[0]!
            a.pixelFormat = view.colorPixelFormat
            a.isBlendingEnabled = true
            a.rgbBlendOperation = .add; a.alphaBlendOperation = .add
            a.sourceRGBBlendFactor = .sourceAlpha; a.sourceAlphaBlendFactor = .one
            a.destinationRGBBlendFactor = .oneMinusSourceAlpha; a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let n = pipeline("vmain"), let h = pipeline("vhigh") else { return nil }
        normalPipeline = n
        highlightPipeline = h
        super.init()
        view.delegate = self
    }

    func setPoints(xy: [Float], clusters ids: [UInt8]) {
        pointCount = ids.count
        setVisibility(nil)
        positions = xy.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: max(8, $0.count), options: .storageModeShared) }
        setClusters(ids)
    }

    /// One flag per point; nil shows everything. Hidden points are not drawn.
    func setVisibility(_ mask: [Bool]?) {
        let bytes = (mask ?? [Bool](repeating: true, count: pointCount)).map { UInt8($0 ? 1 : 0) }
        visibility = bytes.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: max(1, $0.count), options: .storageModeShared) }
    }

    /// Replaces the 24 dot colours (the default is the cluster palette).
    func setPalette(_ colors: [NSColor]?) {
        palette = (0..<Palette.count).map { i in
            guard let colors, i < colors.count, let c = colors[i].usingColorSpace(.deviceRGB) else { return Palette.simd(i) }
            return SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1)
        }
    }

    func setClusters(_ ids: [UInt8]) {
        clusters = ids.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: max(1, $0.count), options: .storageModeShared) }
    }

    func setHighlights(_ entries: [HighlightEntry]) {
        highlightCount = entries.count
        highlights = entries.isEmpty ? nil : entries.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let positions, let clusters, let visibility, pointCount > 0 {
            var u = uniformsProvider()
            enc.setRenderPipelineState(normalPipeline)
            enc.setVertexBuffer(positions, offset: 0, index: 0)
            enc.setVertexBuffer(clusters, offset: 0, index: 1)
            enc.setVertexBuffer(visibility, offset: 0, index: 2)
            enc.setVertexBytes(&u, length: MemoryLayout<MapUniforms>.stride, index: 3)
            palette.withUnsafeBytes { enc.setVertexBytes($0.baseAddress!, length: $0.count, index: 4) }
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCount)

            if let highlights, highlightCount > 0 {
                enc.setRenderPipelineState(highlightPipeline)
                enc.setVertexBuffer(highlights, offset: 0, index: 5)
                enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: highlightCount)
            }
        }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
