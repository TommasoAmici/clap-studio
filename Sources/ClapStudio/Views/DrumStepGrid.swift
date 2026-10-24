import ClapCore
import SwiftUI

/// Keeps the sound controls, steps and mixer aligned across the drum tracks.
enum DrumGridLayout {
    static let soundWidth = 278.0
    static let mixWidth = 136.0
    static let barWidth = 456.0
    static func maximumScroll(bars: Int, width: Double) -> Double { max(0, Double(bars) * barWidth - width) }
}

/// A window onto the pattern, sharing its horizontal position with every other track.
struct DrumStepGrid: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let track: DrumTrack
    @Binding var scroll: Double

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let maximum = DrumGridLayout.maximumScroll(bars: model.drumPattern.bars, width: width)
            let left = min(max(0, scroll), maximum)
            let first = Int(left / DrumGridLayout.barWidth)
            let last = min(model.drumPattern.bars, Int((left + width) / DrumGridLayout.barWidth) + 1)
            HStack(spacing: 12) {
                ForEach(first..<last, id: \.self) { bar in
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { beat in
                            HStack(spacing: 3) {
                                ForEach(0..<4, id: \.self) { division in
                                    let step = bar * DrumPattern.stepCount + beat * 4 + division
                                    StepCell(on: track.hits.indices.contains(step) && track.hits[step], playing: model.drumStep == step, beat: division == 0)
                                        .onTapGesture { model.drumPattern.toggle(track: index, step: step) }
                                        .accessibilityLabel("\(track.label), bar \(bar + 1), step \(beat * 4 + division + 1)")
                                        .accessibilityValue(track.hits.indices.contains(step) && track.hits[step] ? "On" : "Off")
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { model.drumPattern.toggle(track: index, step: step) }
                                }
                            }
                        }
                    }
                    .frame(width: DrumGridLayout.barWidth - 12, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: true)
                }
            }
            .fixedSize(horizontal: true, vertical: true)
            .offset(x: Double(first) * DrumGridLayout.barWidth - left, y: 15)
            .frame(width: width, height: 39, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                Canvas { context, _ in
                    for bar in first..<last {
                        let x = Double(bar) * DrumGridLayout.barWidth - left
                        context.draw(Text("Bar \(bar + 1)").font(.caption2).foregroundColor(.secondary),
                                     at: CGPoint(x: x, y: 6), anchor: .leading)
                    }
                }
                .frame(height: 14).allowsHitTesting(false)
            }
            .clipped()
            .background(SidewaysScroll { points in scroll = min(max(0, left - points), maximum) })
            .onChange(of: model.drumBar) { _, bar in
                let start = Double(bar) * DrumGridLayout.barWidth
                let end = start + DrumGridLayout.barWidth
                if start < left || end > left + width { scroll = min(start, maximum) }
            }
            .onChange(of: maximum) { _, value in scroll = min(scroll, value) }
        }
        .frame(height: 39)
    }
}

/// The piano roll's slider alternative to a sideways swipe, aligned with the drum steps.
struct DrumScrollControl: View {
    @Environment(AppModel.self) private var model
    @Binding var scroll: Double

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: DrumGridLayout.soundWidth)
            GeometryReader { geometry in
                let maximum = DrumGridLayout.maximumScroll(bars: model.drumPattern.bars, width: max(1, geometry.size.width))
                if maximum > 0 {
                    Slider(value: Binding(get: { min(max(0, scroll), maximum) }, set: { scroll = $0 }), in: 0...maximum)
                        .controlSize(.mini)
                        .accessibilityLabel("Scroll drum bars")
                        .help("Scroll across the drum pattern. You can also swipe sideways over the steps or hold Shift while scrolling.")
                }
            }
            Color.clear.frame(width: DrumGridLayout.mixWidth)
        }
        .frame(height: 18)
    }
}

private struct StepCell: View {
    let on: Bool
    let playing: Bool
    let beat: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(on ? Color.accentColor : Color.secondary.opacity(beat ? 0.32 : 0.18))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(playing ? Color.white.opacity(0.9) : .clear, lineWidth: 1.5))
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
    }
}
