import ClapCore
import SwiftUI

/// Shades what a trim leaves out and gives it two draggable edges on the waveform.
struct TrimOverlay: View {
    let trim: SampleTrim
    let duration: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let startX = width * trim.start / duration, endX = width * trim.end / duration
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.black.opacity(0.55)).frame(width: max(0, startX), height: height).allowsHitTesting(false)
            Rectangle().fill(Color.black.opacity(0.55)).frame(width: max(0, width - endX), height: height)
                .offset(x: endX).allowsHitTesting(false)
            TrimEdge(isStart: true, x: startX, duration: duration, width: width, height: height)
            TrimEdge(isStart: false, x: endX, duration: duration, width: width, height: height)
        }
    }
}

private struct TrimEdge: View {
    @Environment(AppModel.self) private var model
    let isStart: Bool
    let x: CGFloat
    let duration: Double
    let width: CGFloat
    let height: CGFloat
    @State private var dragX: CGFloat?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.green).frame(width: 2)
            Image(systemName: isStart ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill")
                .font(.system(size: 10)).foregroundStyle(.green)
                .offset(x: isStart ? 7 : -7, y: -height / 2 + 9)
        }
        .frame(width: 16, height: height)
        .contentShape(Rectangle())
        .offset(x: (dragX ?? x) - 8)
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { dragX = max(0, min(width, x + $0.translation.width)) }
                .onEnded { value in
                    let final = max(0, min(width, x + value.translation.width))
                    dragX = nil
                    let seconds = duration * final / width
                    if isStart { model.setTrimStart(atSeconds: seconds) } else { model.setTrimEnd(atSeconds: seconds) }
                })
        .help(isStart ? "Drag to move where the sound starts" : "Drag to move where the sound ends")
    }
}
