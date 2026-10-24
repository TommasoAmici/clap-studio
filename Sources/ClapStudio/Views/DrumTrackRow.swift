import ClapCore
import SwiftUI

struct DrumTrackRow: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let track: DrumTrack
    let title: String
    @Binding var scroll: Double
    private var dropTargeted: Bool { model.dropHover == .drumTrack(index) }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { model.select(track.sampleID, play: true) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(.caption.bold()).lineLimit(1)
                        if model.sampleByID[track.sampleID] == nil {
                            Label(model.drumSampleName(track), systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.orange).lineLimit(1)
                        } else {
                            Text(model.drumSampleName(track)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(width: 110, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(track.sampleID == DrumTrack.unassignedSampleID ? "Drop a sample here, or use the selected sample, to hear this track." : model.sampleByID[track.sampleID] == nil
                      ? "This sample is no longer in the library. Drop another sample here to replace it."
                      : "Preview this sound")
                .disabled(track.sampleID == DrumTrack.unassignedSampleID)
                // Always laid out, so the steps line up on every row; hidden when the kit offers no other sound.
                let hasAlternatives = track.alternatives.count > 1
                HStack(spacing: 2) {
                    Button { model.cycleDrumSample(track: index, by: -1) } label: { Image(systemName: "chevron.left") }
                    Button { model.cycleDrumSample(track: index, by: 1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless).help("Try another sound from the kit")
                .opacity(hasAlternatives ? 1 : 0).disabled(!hasAlternatives).accessibilityHidden(!hasAlternatives)
                HStack(spacing: 2) {
                    Button { model.swapDrumSound(track: index) } label: { Image(systemName: "dice") }
                        .disabled(model.sampleByID[track.sampleID] == nil)
                        .help("Try a similar sound here")
                    Button { model.undoDrumSwap(track: index) } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(track.history.isEmpty)
                        .help("Go back to the previous sound")
                    Button { model.toggleDrumLock(track: index) } label: { Image(systemName: track.locked ? "lock.fill" : "lock.open") }
                        .foregroundStyle(track.locked ? Color.accentColor : Color.secondary)
                        .help(track.locked ? "Locked: Shuffle Kit leaves this sound alone" : "Lock this sound so Shuffle Kit keeps it")
                }
                .buttonStyle(.borderless)
                Button { if let id = model.selectedID { model.replaceDrumSample(track: index, with: id) } } label: {
                    Image(systemName: "arrow.left.arrow.right.square")
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedID == nil || model.selectedID == track.sampleID)
                .help("Replace this sound with the selected sample (or drag a sample onto the track)")
            }
            .frame(width: DrumGridLayout.soundWidth, alignment: .leading)
            DrumStepGrid(index: index, track: track, scroll: $scroll)
            HStack(spacing: 8) {
                toggle("M", on: track.muted, color: .orange, help: "Mute") { model.drumPattern.tracks[index].muted.toggle() }
                toggle("S", on: track.solo, color: .yellow, help: "Solo") { model.drumPattern.tracks[index].solo.toggle() }
                Slider(value: Binding(get: { Double(track.volume) },
                                      set: { model.drumPattern.tracks[index].volume = Float($0) }), in: 0...1)
                    .frame(width: 56).controlSize(.mini)
                Button { model.drumPattern.removeTrack(at: index) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("Remove this track")
            }
            .frame(width: DrumGridLayout.mixWidth, alignment: .trailing)
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(dropTargeted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: dropTargeted ? 1.5 : 0))
        .dropZone(.drumTrack(index))
        .contextMenu {
            if let id = model.selectedID, id != track.sampleID {
                Button("Use Selected Sample Here") { model.replaceDrumSample(track: index, with: id) }
            }
        }
    }

    private func toggle(_ title: String, on: Bool, color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption2.bold()).frame(width: 18, height: 18)
                .background(on ? color : Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(on ? Color.black : Color.secondary)
        }
        .buttonStyle(.plain).help(help)
    }
}
