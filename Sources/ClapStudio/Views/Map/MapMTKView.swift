import AppKit
import ClapCore
import MetalKit
import simd

/// Interactive map surface: pan (drag), zoom (pinch / scroll), hover-to-play, click-to-select
/// and drag-out of the dot under the cursor as a real file drag.
final class MapMTKView: MTKView, NSDraggingSource {
    // Callbacks
    var onHover: (Int?) -> Void = { _ in }
    var onClick: (Int) -> Void = { _ in }
    var urlForRow: (Int) -> URL? = { _ in nil }
    var onGrab: (Int) -> Void = { _ in }

    private(set) var renderer: MapRenderer?
    private var grid = SpatialGrid(xy: [])
    private var pointCount = 0
    private var visibleMask: [Bool]?     // nil: every point is shown

    // View transform: world point at the view centre, and points per world unit.
    private var center = SIMD2<Float>(0, 0)
    private var scale: Float = 100
    private var fitScale: Float = 100

    // Highlight state
    private var selectedRow: Int?
    private var similarRows: [Int] = []
    private(set) var hoverRow: Int?

    // Mouse tracking
    private var downHit: Int?
    private var downPoint: NSPoint = .zero
    private var draggedOut = false
    private var hoverTask: DispatchWorkItem?

    private let hitRadiusPoints: Float = 7

    init() {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        renderer = MapRenderer(view: self)
        renderer?.uniformsProvider = { [unowned self] in self.uniforms() }
        layer?.isOpaque = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: data

    func setData(xy: [Float], clusters: [Int32], refit: Bool) {
        pointCount = clusters.count
        visibleMask = nil
        renderer?.setPoints(xy: xy, clusters: clusters.map { UInt8(truncatingIfNeeded: $0) })
        grid = SpatialGrid(xy: xy)
        if refit { fitToData() }
        refreshHighlights()
    }

    /// Shows only the flagged points (the sidebar filters); nil shows all. Hover and clicks ignore hidden dots.
    func setVisibility(_ mask: [Bool]?) {
        visibleMask = mask
        renderer?.setVisibility(mask)
        if let h = hoverRow, !isVisible(h) { setHover(nil) }
        refreshHighlights()
    }

    private func isVisible(_ row: Int) -> Bool { visibleMask?[row] ?? true }

    func setClusters(_ clusters: [Int32]) {
        renderer?.setClusters(clusters.map { UInt8(truncatingIfNeeded: $0) })
        needsDisplay = true
    }

    func setSelection(selected: Int?, similar: [Int]) {
        guard selected != selectedRow || similar != similarRows else { return }
        selectedRow = selected
        similarRows = similar
        refreshHighlights()
    }

    private func refreshHighlights() {
        var entries = similarRows.filter(isVisible).map { HighlightEntry(index: UInt32($0), kind: 1) }
        if let h = hoverRow, isVisible(h) { entries.append(HighlightEntry(index: UInt32(h), kind: 3)) }
        if let s = selectedRow, isVisible(s) { entries.append(HighlightEntry(index: UInt32(s), kind: 2)) }
        renderer?.setHighlights(entries)
        needsDisplay = true
    }

    func fitToData() {
        guard pointCount > 0, bounds.width > 1, bounds.height > 1 else { return }
        let w = max(grid.maxX - grid.minX, 1e-4), h = max(grid.maxY - grid.minY, 1e-4)
        center = SIMD2((grid.minX + grid.maxX) / 2, (grid.minY + grid.maxY) / 2)
        fitScale = Float(min(bounds.width, bounds.height) / 1.0) / max(w, h) * 0.9
        scale = fitScale
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let first = bounds.width <= 1
        super.setFrameSize(newSize)
        if first { fitToData() }
        needsDisplay = true
    }

    // MARK: rendering parameters

    private func uniforms() -> MapUniforms {
        let zoom = max(scale / max(fitScale, 1e-6), 0.01)
        let base: Float = pointCount > 30_000 ? 2.2 : (pointCount > 8_000 ? 3.2 : 5)
        let size = min(26, base * powf(zoom, 0.38))
        let backing = Float(window?.backingScaleFactor ?? 2)
        return MapUniforms(center: center, viewport: SIMD2(Float(bounds.width), Float(bounds.height)),
                           scale: scale, pointSize: size * backing,
                           alpha: selectedRow == nil ? 0.88 : 0.5)
    }

    private func world(_ p: NSPoint) -> SIMD2<Float> {
        center + SIMD2(Float(p.x - bounds.width / 2), Float(p.y - bounds.height / 2)) / scale
    }

    private func hit(at p: NSPoint) -> Int? {
        guard let mask = visibleMask else { return grid.nearest(to: world(p), within: hitRadiusPoints / scale) }
        return grid.nearest(to: world(p), within: hitRadiusPoints / scale) { mask[$0] }
    }

    // MARK: hover

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) { updateHover(convert(event.locationInWindow, from: nil)) }

    override func mouseExited(with event: NSEvent) { setHover(nil) }

    private func updateHover(_ p: NSPoint) { setHover(hit(at: p)) }

    private func setHover(_ row: Int?) {
        guard row != hoverRow else { return }
        hoverRow = row
        refreshHighlights()
        hoverTask?.cancel()
        // A short debounce keeps fast sweeps across the map from firing a sound per dot.
        let task = DispatchWorkItem { [weak self] in self?.onHover(row) }
        hoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(row == nil ? 0 : 35), execute: task)
        NSCursor.current.set()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // MARK: pan, click, drag-out

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        downPoint = p
        downHit = hit(at: p)
        draggedOut = false
        if event.clickCount == 2 && downHit == nil { fitToData() }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let row = downHit {
            if !draggedOut, hypot(p.x - downPoint.x, p.y - downPoint.y) > 4, let url = urlForRow(row) {
                draggedOut = true
                onGrab(row)
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                item.setDraggingFrame(NSRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32),
                                      contents: NSWorkspace.shared.icon(forFile: url.path))
                beginDraggingSession(with: [item], event: event, source: self)
            }
            return
        }
        center -= SIMD2(Float(event.deltaX), -Float(event.deltaY)) / scale
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let row = downHit, !draggedOut { onClick(row) }
        downHit = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    // MARK: zoom

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let trackpadPan = event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.option)
        if trackpadPan {
            center -= SIMD2(Float(event.scrollingDeltaX), -Float(event.scrollingDeltaY)) / scale
            needsDisplay = true
        } else {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 120 : event.scrollingDeltaY / 12
            zoom(by: Float(exp(delta)), around: p)
        }
        updateHover(p)
    }

    override func magnify(with event: NSEvent) {
        zoom(by: Float(1 + event.magnification), around: convert(event.locationInWindow, from: nil))
    }

    private func zoom(by factor: Float, around p: NSPoint) {
        let before = world(p)
        scale = min(max(scale * factor, fitScale * 0.5), fitScale * 400)
        center += before - world(p)     // keep the point under the cursor fixed
        needsDisplay = true
    }
}
