import ClapCore
import SwiftUI

/// Waveform with playhead and draggable cue markers.
/// Click: play from there and keep that spot as the start marker (M sets a cue on it). Option-click: add a cue. Drag a flag: move it. Right-click a flag: delete.
struct WaveformCueView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let duration = max(model.selectedDuration, 0.001)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                WaveformShape(peaks: model.waveform)
                    .fill(Color.accentColor.opacity(0.85))
                    .padding(.vertical, 6)

                TimelineView(.animation(minimumInterval: 1 / 60, paused: model.playback.sampleID != model.selectedID)) { _ in
                    if model.playback.sampleID == model.selectedID, let t = model.playback.playhead() {
                        Rectangle().fill(Color.primary).frame(width: 1.5)
                            .offset(x: geo.size.width * t / duration)
                    }
                }
                .allowsHitTesting(false)

                if let trim = model.selectedTrim {
                    TrimOverlay(trim: trim, duration: duration, width: geo.size.width, height: geo.size.height)
                }

                if let marker = model.startMarkerSeconds {
                    StartMarker(height: geo.size.height)
                        .offset(x: geo.size.width * marker / duration - 5)
                        .allowsHitTesting(false)
                }

                ForEach(Array(model.cues.enumerated()), id: \.element.id) { index, cue in
                    CueMarker(cue: cue, number: index + 1, duration: duration, width: geo.size.width,
                              height: geo.size.height)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                let seconds = max(0, min(duration, duration * tap.location.x / geo.size.width))
                if NSEvent.modifierFlags.contains(.option) { model.addCue(atSeconds: seconds) }
                else { model.placeStartMarker(atSeconds: seconds) }
            })
        }
        .frame(height: 110)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if model.waveform.isEmpty && model.selectedID != nil { ProgressView().controlSize(.small) }
        }
    }
}

/// Where the user last clicked to audition; stays put while the playhead moves on.
private struct StartMarker: View {
    let height: CGFloat
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Color.cyan).frame(width: 1.5, height: height)
            Image(systemName: "triangleshape.fill").resizable().frame(width: 10, height: 8)
                .rotationEffect(.degrees(180)).foregroundStyle(.cyan)
        }
        .frame(width: 10, height: height)
    }
}

private struct WaveformShape: Shape {
    let peaks: [Float]   // (min, max) pairs

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bins = peaks.count / 2
        guard bins > 0 else { return path }
        let mid = rect.midY, half = rect.height / 2
        let step = rect.width / CGFloat(bins)
        for i in 0..<bins {
            let top = mid - CGFloat(min(1, peaks[i * 2 + 1])) * half
            let bottom = mid - CGFloat(max(-1, peaks[i * 2])) * half
            path.addRect(CGRect(x: rect.minX + CGFloat(i) * step, y: top,
                                width: max(1, step - 0.5), height: max(1, bottom - top)))
        }
        return path
    }
}

private struct CueMarker: View {
    @Environment(AppModel.self) private var model
    let cue: CuePoint
    let number: Int
    let duration: Double
    let width: CGFloat
    let height: CGFloat
    @State private var dragX: CGFloat?

    private var storedX: CGFloat { width * model.seconds(for: cue) / duration }

    var body: some View {
        let selected = model.selectedCueID == cue.id
        let color: Color = selected ? .yellow : .orange
        ZStack(alignment: .top) {
            Rectangle().fill(color).frame(width: 1.5)
            Text("\(number)").font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(color, in: RoundedRectangle(cornerRadius: 3))
        }
        .frame(width: 18, height: height)
        .contentShape(Rectangle())
        .offset(x: (dragX ?? storedX) - 9)
        .highPriorityGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { dragX = max(0, min(width, storedX + $0.translation.width)) }
                .onEnded { value in
                    let final = max(0, min(width, storedX + value.translation.width))
                    dragX = nil
                    model.moveCue(cue.id, toSeconds: duration * final / width)
                })
        .onTapGesture { model.playCue(cue) }
        .contextMenu {
            Button("Delete Cue", role: .destructive) { model.removeCue(cue.id) }
        }
        .help(cue.label.isEmpty ? "Cue \(number)" : cue.label)
    }
}
