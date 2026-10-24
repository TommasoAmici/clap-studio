#if DEBUG
import AppKit
import MapKit

/// MapKit's live layers omit pins during bitmap caching; render the basemap and runtime places into an image.
@MainActor
enum DebugSnapshotPlaces {
    static func overlay(model: AppModel, media: Bool) async -> NSImageView? {
        guard let root = NSApp.windows.first(where: \.isVisible)?.contentView,
              let map = findMap(in: root), let parent = map.superview else { return nil }
        let bounds = CGRect(origin: .zero, size: map.bounds.size)
        var rect = map.visibleMapRect
        if media {
            let points = model.placePins.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.center.latitude, longitude: $0.center.longitude)) }
            let minY = points.map(\.y).min() ?? MKMapRect.world.midY
            let maxY = points.map(\.y).max() ?? MKMapRect.world.midY
            let height = MKMapRect.world.width * bounds.height / bounds.width
            rect = MKMapRect(x: 0, y: (minY + maxY - height) / 2, width: MKMapRect.world.width, height: height)
        }
        do {
            // Native camera fitting caps the world extent. Two projected halves keep this capture seamless.
            let parts = media ? 2 : 1
            var snapshots: [MKMapSnapshotter.Snapshot] = []
            for part in 0..<parts {
                let options = MKMapSnapshotter.Options()
                options.mapRect = MKMapRect(x: rect.minX + Double(part) * rect.width / Double(parts), y: rect.minY,
                                           width: rect.width / Double(parts), height: rect.height)
                options.size = CGSize(width: bounds.width / Double(parts), height: bounds.height)
                options.mapType = map.mapType
                options.appearance = NSApp.effectiveAppearance
                snapshots.append(try await MKMapSnapshotter(options: options).start())
            }
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            for (part, snapshot) in snapshots.enumerated() {
                snapshot.image.draw(in: CGRect(x: Double(part) * bounds.width / Double(parts), y: 0,
                                               width: bounds.width / Double(parts), height: bounds.height))
            }
            for pin in model.placePins {
                let projected = MKMapPoint(CLLocationCoordinate2D(latitude: pin.center.latitude, longitude: pin.center.longitude))
                let point = CGPoint(x: (projected.x - rect.minX) / rect.width * bounds.width,
                                    y: bounds.height - (projected.y - rect.minY) / rect.height * bounds.height)
                let diameter = min(34, 16 + CGFloat(log2(Double(max(pin.count, 1)))) * 3)
                let circle = NSBezierPath(ovalIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                                        width: diameter, height: diameter))
                let selected = model.placeSelectionID == pin.id
                (selected ? NSColor.controlAccentColor : NSColor.systemRed.withAlphaComponent(0.85)).setFill()
                circle.fill()
                NSColor.white.setStroke(); circle.lineWidth = selected ? 2.5 : 1.5; circle.stroke()
                if pin.count > 1 {
                    let label = NSAttributedString(string: String(pin.count), attributes: [
                        .font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.white])
                    let size = label.size()
                    label.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
                }
            }
            image.unlockFocus()
            let overlay = NSImageView(frame: map.convert(map.bounds, to: parent))
            overlay.image = image
            overlay.imageScaling = .scaleAxesIndependently
            parent.addSubview(overlay, positioned: .above, relativeTo: map)
            return overlay
        } catch {
            NSLog("Could not render the Places map: %@", error.localizedDescription)
            return nil
        }
    }

    private static func findMap(in view: NSView) -> MKMapView? {
        if let map = view as? MKMapView { return map }
        for child in view.subviews { if let map = findMap(in: child) { return map } }
        return nil
    }
}
#endif
