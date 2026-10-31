import ClapCore
import SwiftUI

/// The samples about to be sent, in order. For a bank each row shows its channel (and bank, when samples go to following
/// banks) and lets you choose another; for the Pool it is a plain list.
struct SquidExportItems: View {
    @Environment(AppModel.self) private var model
    let toPool: Bool
    /// The samples are joined first, so rows have no channel of their own: they are sounds in an order.
    let joining: Bool
    let sameChannel: Bool
    let plan: SquidChannelPlan
    @State private var dropTargeted = false

    private var perSample: Bool { !toPool && !joining }

    var body: some View {
        let samples = model.squidItems.compactMap { model.sampleByID[$0] }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(toPool ? "\(model.samplesPhrase(samples.count))" : (joining ? "Sound order" : "Channels")).font(.subheadline.bold())
                Spacer()
                if perSample, !model.squidChannels.isEmpty {
                    Button("Automatic Channels") { model.squidChannels = [:] }
                        .controlSize(.small).help("Forget the channels you picked and place the samples in order again.")
                }
                Button("Add Selected") { model.squidItems += model.actionTargets.filter { !model.squidItems.contains($0) } }
                    .controlSize(.small).disabled(model.actionTargets.isEmpty)
                Button("From Drums") { model.squidItems += model.drumPattern.tracks.map(\.sampleID).filter { !model.squidItems.contains($0) } }
                    .controlSize(.small).disabled(model.drumPattern.tracks.isEmpty)
            }
            List {
                ForEach(Array(model.squidItems.enumerated()), id: \.element) { index, id in row(index: index, id: id) }
                    .onMove { model.squidItems.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 200)
            .overlay { if model.squidItems.isEmpty { Text("Drag samples here, or add them with the buttons above").foregroundStyle(.secondary) } }
            .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2) } }
            .fileDrop(isTargeted: $dropTargeted) { urls in
                let new = model.librarySamples(forFiles: urls).map(\.id).filter { !model.squidItems.contains($0) }
                model.squidItems += new
            }
            if joining {
                let files = plan.slots.count
                let banks = plan.slots.compactMap { $0?.bank }
                Text(files == 0 ? "" : "Joins into about \(files) \(files == 1 ? "file" : "files")"
                     + (banks.isEmpty ? "." : ", on channel \(plan.slots.compactMap { $0?.channel }.first ?? 1) of "
                        + (banks.count == 1 ? "bank \(banks[0])." : "banks \(banks.min()!) to \(banks.max()!)."))
                     + (files == 0 ? "" : " The exact count is known once they are joined."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !toPool {
                ForEach(Array(plan.issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue.message).font(.caption).foregroundStyle(issue.isBlocking ? Color.red : Color.orange)
                }
            }
        }
    }

    private func row(index: Int, id: Int64) -> some View {
        let slot = perSample && index < plan.slots.count ? plan.slots[index] : nil
        let overflow = perSample && slot == nil
        return HStack {
            if joining { Text("\(index + 1)").frame(width: 18).foregroundStyle(.secondary).monospacedDigit() }
            if perSample { channelMenu(id: id, slot: slot) }
            if perSample, sameChannel, let slot {
                Text("Bank \(slot.bank)").font(.caption).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            }
            if let sample = model.sampleByID[id] {
                Text(sample.name).lineLimit(1)
            } else {
                Label("Missing sample", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(1)
            }
            if let sample = model.sampleByID[id], sample.duration > SquidLayout.maxSeconds, model.activeTrim(for: sample) == nil {
                Text("cut at \(Int(SquidLayout.maxSeconds)) s").font(.caption2).foregroundStyle(.orange)
            }
            Spacer()
            if overflow { Text("not sent").font(.caption2).foregroundStyle(.secondary) }
            Button { model.squidItems.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
        }
        .opacity(overflow ? 0.5 : 1)
    }

    /// The channel of a row. A number in the accent colour was picked by you; grey ones follow the order.
    private func channelMenu(id: Int64, slot: SquidSlot?) -> some View {
        let picked = model.squidChannels[id]
        let conflict = slot.map { problem(with: $0) } ?? false
        let overwritten = slot.map { overwrites($0) } ?? false
        return Menu {
            ForEach(1...SquidLayout.slotsPerBank, id: \.self) { channel in
                Button { model.squidChannels[id] = channel } label: {
                    if channel == slot?.channel { Label("Channel \(channel)", systemImage: "checkmark") } else { Text("Channel \(channel)") }
                }
            }
            Divider()
            Button("Automatic") { model.squidChannels[id] = nil }.disabled(picked == nil)
        } label: {
            Text(slot.map { String($0.channel) } ?? "–").monospacedDigit()
                .foregroundStyle(conflict ? Color.red : (overwritten ? Color.orange : (picked == nil ? Color.secondary : Color.accentColor)))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Channel on the module. Choose another, or Automatic to follow the order.")
        .accessibilityLabel(slot.map { "Channel \($0.channel)" } ?? "Not sent")
    }

    /// Whether the sample going to this slot replaces one that is on the stick.
    private func overwrites(_ slot: SquidSlot) -> Bool { plan.issues.contains(.overwritesChannel(bank: slot.bank, channel: slot.channel)) }

    /// Whether a slot is one a plan issue is about (two samples on it, or a sample already there).
    private func problem(with slot: SquidSlot) -> Bool {
        plan.issues.contains {
            switch $0 {
            case .duplicateChannel(let bank, let channel), .channelTaken(let bank, let channel):
                return bank == slot.bank && channel == slot.channel
            default: return false
            }
        }
    }
}
