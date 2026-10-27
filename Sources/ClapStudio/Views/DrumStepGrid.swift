import AppKit
import ClapCore
import SwiftUI

/// Keeps the sound controls, steps and mixer aligned across the drum tracks.
enum DrumGridLayout {
    static let soundWidth = 278.0
    static let mixWidth = 136.0
    static func stepWidth(in width: Double) -> Double { max(13, min(24, (width - 60) / 16)) }
    static func barWidth(in width: Double) -> Double { stepWidth(in: width) * 16 + 72 }
    /// The last bar has no trailing gap; one complete bar fits before scrolling is needed.
    static func maximumScroll(bars: Int, width: Double) -> Double {
        let bar = barWidth(in: width)
        return max(0, (Double(bars) * bar - 12 - width) / bar)
    }
}

/// A window onto the pattern, sharing its horizontal position with every other track.
struct DrumStepGrid: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let track: DrumTrack
    @Binding var scroll: Double                  // bars from the start, so resizing keeps the same place

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let barWidth = DrumGridLayout.barWidth(in: width)
            let stepWidth = DrumGridLayout.stepWidth(in: width)
            let maximum = DrumGridLayout.maximumScroll(bars: model.drumPattern.bars, width: width)
            let left = min(max(0, scroll), maximum)
            let first = Int(left)
            let last = min(model.drumPattern.bars, Int(left + width / barWidth) + 1)
            HStack(spacing: 12) {
                ForEach(first..<last, id: \.self) { bar in
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { beat in
                            HStack(spacing: 3) {
                                ForEach(0..<4, id: \.self) { division in
                                    let step = bar * DrumPattern.stepCount + beat * 4 + division
                                    StepCell(width: stepWidth, on: track.hits.indices.contains(step) && track.hits[step], playing: model.drumStep == step, beat: division == 0)
                                        .onTapGesture { model.drumPattern.toggle(track: index, step: step) }
                                        .accessibilityLabel("\(track.label), bar \(bar + 1), step \(beat * 4 + division + 1)")
                                        .accessibilityValue(track.hits.indices.contains(step) && track.hits[step] ? "On" : "Off")
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { model.drumPattern.toggle(track: index, step: step) }
                                }
                            }
                        }
                    }
                    .frame(width: barWidth - 12, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: true)
                }
            }
            .fixedSize(horizontal: true, vertical: true)
            .offset(x: (Double(first) - left) * barWidth)
            .frame(width: width, height: 22, alignment: .topLeading)
            .clipped()
            .background(SidewaysScroll { points in scroll = min(max(0, left - points / barWidth), maximum) })
            .onChange(of: model.drumBar) { _, bar in
                let start = Double(bar)
                let end = start + (barWidth - 12) / barWidth
                if start < left || end > left + width / barWidth { scroll = min(start, maximum) }
            }
            .onChange(of: maximum) { _, value in scroll = min(scroll, value) }
        }
        .frame(height: 22)
    }
}

/// A native scrollbar shows how much of the pattern is visible, aligned with the drum steps.
struct DrumScrollControl: View {
    @Environment(AppModel.self) private var model
    @Binding var scroll: Double

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: DrumGridLayout.soundWidth)
            GeometryReader { geometry in
                let maximum = DrumGridLayout.maximumScroll(bars: model.drumPattern.bars, width: max(1, geometry.size.width))
                if maximum > 0 {
                    DrumScroller(scroll: $scroll, maximum: maximum,
                                 visibleBars: geometry.size.width / DrumGridLayout.barWidth(in: geometry.size.width))
                        .accessibilityLabel("Scroll drum bars")
                        .help("Scroll across the drum pattern. You can also swipe sideways over the steps or hold Shift while scrolling.")
                }
            }
            Color.clear.frame(width: DrumGridLayout.mixWidth)
        }
        .frame(height: 12)
    }
}

/// Uses the system thumb, page clicks and appearance while all rows share one offset.
private struct DrumScroller: NSViewRepresentable {
    @Binding var scroll: Double
    let maximum: Double
    let visibleBars: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScroller {
        let view = NSScroller(frame: NSRect(x: 0, y: 0, width: 100, height: 12))
        view.scrollerStyle = .overlay
        view.controlSize = .small
        view.target = context.coordinator
        view.action = #selector(Coordinator.scroll(_:))
        view.setAccessibilityLabel("Scroll drum bars")
        return view
    }

    func updateNSView(_ view: NSScroller, context: Context) {
        context.coordinator.parent = self
        view.knobProportion = visibleBars / (visibleBars + maximum)
        view.doubleValue = min(max(0, scroll), maximum) / maximum
    }

    final class Coordinator: NSObject {
        var parent: DrumScroller
        init(_ parent: DrumScroller) { self.parent = parent }

        @objc func scroll(_ sender: NSScroller) {
            let change: Double
            switch sender.hitPart {
            case .decrementLine: change = -0.25
            case .incrementLine: change = 0.25
            case .decrementPage: change = -parent.visibleBars
            case .incrementPage: change = parent.visibleBars
            default:
                parent.scroll = sender.doubleValue * parent.maximum
                return
            }
            parent.scroll = min(max(0, parent.scroll + change), parent.maximum)
        }
    }
}

private struct StepCell: View {
    let width: Double
    let on: Bool
    let playing: Bool
    let beat: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(on ? Color.accentColor : Color.secondary.opacity(beat ? 0.32 : 0.18))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(playing ? Color.white.opacity(0.9) : .clear, lineWidth: 1.5))
            .frame(width: width, height: 22)
            .contentShape(Rectangle())
    }
}
