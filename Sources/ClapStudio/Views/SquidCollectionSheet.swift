import ClapCore
import SwiftUI

/// Sends a collection to a Squid Salmple stick: a new set with a bank per sub-collection, or a new Pool folder.
struct SquidCollectionSheet: View {
    let collectionID: Int64
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var input: AppModel.SquidCollectionInput?
    @State private var driveID: String?
    @State private var busy = false
    @State private var problem: String?

    private var contents: SquidStickContents { driveID.flatMap { model.usbContents[$0] } ?? SquidStickContents() }
    private var plan: SquidCollectionPlan? {
        input.map { SquidCollectionPlan.make(name: $0.name, ownSamples: $0.own, children: $0.children, contents: contents) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send “\(input?.name ?? "Collection")” to Squid Salmple").font(.title3.bold())
            if model.usbDrives.isEmpty {
                Text("Connect a USB stick with an ALM022 folder and it will show up here.").foregroundStyle(.secondary)
            } else {
                Picker("Drive", selection: $driveID) {
                    ForEach(model.usbDrives) { Text($0.name).tag(Optional($0.id)) }
                }
                if let plan { summary(plan) }
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
            Text("Samples are converted to 16-bit, 44.1 kHz mono and cut at \(Int(SquidLayout.maxSeconds)) seconds. Trims are applied"
                 + (model.squidMatchLevels ? " and levels matched" : "") + ". Your library files are not changed.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send") { send() }.keyboardShortcut(.defaultAction).disabled(busy || driveID == nil || plan?.isBlocked != false)
            }
        }
        .padding(16)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            input = model.squidCollectionInput(collectionID)
            driveID = model.usbDrives.first?.id
        }
    }

    @ViewBuilder private func summary(_ plan: SquidCollectionPlan) -> some View {
        switch plan.destination {
        case .set(let name, let banks):
            Text("A new set called “\(name)” with \(banks.count) \(banks.count == 1 ? "bank" : "banks") and \(plan.sampleCount) samples:")
            ForEach(banks, id: \.number) { bank in
                Label("Bank \(bank.number): \(bank.name) (\(bank.samples.count))", systemImage: "square.grid.2x2").font(.callout)
            }
        case .pool(let groups):
            Text("A new folder in the Pool with \(plan.sampleCount) samples" + (groups.count > 1 ? " in \(groups.count) numbered folders:" : ":"))
            ForEach(groups, id: \.path) { group in
                Label("\(group.path.joined(separator: " / ")) (\(group.samples.count))", systemImage: "folder").font(.callout)
            }
        case .none:
            EmptyView()
        }
        ForEach(plan.blockers, id: \.self) { Label($0, systemImage: "xmark.octagon").font(.caption).foregroundStyle(.red) }
        ForEach(plan.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
    }

    private func send() {
        guard let driveID, let plan, !plan.isBlocked else { return }
        busy = true
        problem = nil
        Task {
            let error = await model.sendCollectionToSquid(plan, driveID: driveID)
            busy = false
            if let error { problem = error; return }
            dismiss()
        }
    }
}
