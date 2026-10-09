import ClapCore
import SwiftUI

/// Sends samples to a Squid Salmple stick: eight at a time into a bank, or any number into the Pool.
struct SquidExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var driveID: String?
    @State private var toPool = false
    @State private var setChoice = Self.defaultSet          // a set name, or `newSet`
    @State private var newSetName = ""
    @State private var bankNumber = 1
    @State private var bankName = ""
    @State private var replace = false
    @State private var poolFolder = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var dropTargeted = false

    private static let defaultSet = ""
    private static let newSet = "\u{1}new"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send to Squid Salmple").font(.title3.bold())
            if model.usbDrives.isEmpty {
                Text("Connect a USB stick with an ALM022 folder and it will show up here.").foregroundStyle(.secondary)
            } else {
                destination
                Divider()
                items
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
            Text("Samples are converted to 16-bit, 44.1 kHz mono (what the module plays) and cut at \(Int(SquidLayout.maxSeconds)) seconds. "
                 + "Trims are applied. Your library files are not changed.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send") { send() }.keyboardShortcut(.defaultAction).disabled(!canSend)
            }
        }
        .padding(16)
        .frame(width: 520)
        .onAppear(perform: configure)
        .onChange(of: driveID) { _, _ in pickFreeBank() }
        .onChange(of: setChoice) { _, _ in pickFreeBank() }
        .onChange(of: bankNumber) { _, _ in replace = false }
    }

    // MARK: destination

    private var drive: UsbDrive? { driveID.flatMap { model.drive(id: $0) } }
    private var contents: SquidStickContents { driveID.flatMap { model.usbContents[$0] } ?? SquidStickContents() }
    private var chosenSet: String? { setChoice == Self.defaultSet ? nil : (setChoice == Self.newSet ? SquidLayout.cleanSetName(newSetName) : setChoice) }
    private var existingBank: SquidBank? { contents.set(named: chosenSet)?.banks.first { $0.number == bankNumber } }
    private var tooManySets: Bool { setChoice == Self.newSet && contents.namedSetCount >= SquidLayout.maxSets }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Drive", selection: $driveID) {
                ForEach(model.usbDrives) { Text($0.name).tag(Optional($0.id)) }
            }
            if let drive, !drive.isFAT32 {
                Label("This drive is formatted as \(drive.formatDescription). The module reads FAT32.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Picker("Into", selection: $toPool) {
                Text("A bank").tag(false)
                Text("The Pool").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            if toPool {
                TextField("Folder inside Pool (optional)", text: $poolFolder).textFieldStyle(.roundedBorder)
                Text("The Pool holds loose samples the module can load into any channel. Up to \(SquidLayout.maxEntriesPerFolder) entries per folder.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                bankFields
            }
        }
    }

    private var bankFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Set", selection: $setChoice) {
                Text("Default").tag(Self.defaultSet)
                ForEach(contents.sets.compactMap(\.name), id: \.self) { Text($0).tag($0) }
                Text("New set…").tag(Self.newSet)
            }
            if setChoice == Self.newSet {
                TextField("Set name (up to \(SquidLayout.maxSetNameLength) letters)", text: $newSetName).textFieldStyle(.roundedBorder)
                if tooManySets {
                    Text("The module reads at most \(SquidLayout.maxSets) sets.").font(.caption).foregroundStyle(.red)
                }
            }
            HStack {
                Picker("Bank", selection: $bankNumber) {
                    ForEach(1...SquidLayout.maxBanksPerSet, id: \.self) { n in
                        let used = contents.set(named: chosenSet)?.banks.first { $0.number == n }
                        Text(used == nil ? "Bank \(n)" : "Bank \(n) (\(used?.name.isEmpty == false ? used!.name : "in use"))").tag(n)
                    }
                }
                TextField("Name (up to \(SquidLayout.maxNameLength) letters)", text: $bankName).textFieldStyle(.roundedBorder)
            }
            let shown = SquidLayout.cleanBankName(bankName)
            if !shown.isEmpty { Text("Shown on the module as \"\(shown)\"").font(.caption).foregroundStyle(.secondary) }
            if existingBank != nil {
                Toggle("Replace the existing bank (it is moved to the Trash)", isOn: $replace).font(.caption)
            }
        }
    }

    // MARK: samples

    private var items: some View {
        let samples = model.squidItems.compactMap { model.sampleByID[$0] }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(toPool ? "\(model.samplesPhrase(samples.count))" : "Channels").font(.subheadline.bold())
                Spacer()
                Button("Add Selected") { model.squidItems += model.actionTargets.filter { !model.squidItems.contains($0) } }
                    .controlSize(.small).disabled(model.actionTargets.isEmpty)
                Button("From Drums") { model.squidItems += model.drumPattern.tracks.map(\.sampleID).filter { !model.squidItems.contains($0) } }
                    .controlSize(.small).disabled(model.drumPattern.tracks.isEmpty)
            }
            List {
                ForEach(Array(model.squidItems.enumerated()), id: \.element) { index, id in
                    let overflow = !toPool && index >= SquidLayout.slotsPerBank
                    HStack {
                        Text(toPool ? "" : (overflow ? "–" : "\(index + 1)")).frame(width: 18).foregroundStyle(.secondary).monospacedDigit()
                        if let sample = model.sampleByID[id] {
                            Text(sample.name).lineLimit(1)
                        } else {
                            Label("Missing sample", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).lineLimit(1)
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
                .onMove { model.squidItems.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 200)
            .overlay { if model.squidItems.isEmpty { Text("Drag samples here, or add them with the buttons above").foregroundStyle(.secondary) } }
            .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2) } }
            .fileDrop(isTargeted: $dropTargeted) { urls in
                let new = model.librarySamples(forFiles: urls).map(\.id).filter { !model.squidItems.contains($0) }
                model.squidItems += new
            }
            if !toPool, model.squidItems.count > SquidLayout.slotsPerBank {
                Text("A bank holds \(SquidLayout.slotsPerBank) samples. Only the first \(SquidLayout.slotsPerBank) are sent.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: actions

    private var canSend: Bool {
        guard !busy, drive != nil, !model.squidItems.isEmpty else { return false }
        if toPool { return true }
        if setChoice == Self.newSet && (SquidLayout.cleanSetName(newSetName).isEmpty || tooManySets) { return false }
        return existingBank == nil || replace
    }

    private func configure() {
        let target = model.squidTarget
        driveID = target.drive ?? model.usbDrives.first?.id
        toPool = target.pool
        setChoice = target.set ?? Self.defaultSet
        pickFreeBank()
    }

    private func pickFreeBank() {
        replace = false
        guard existingBank != nil, let free = contents.freeBankNumbers(inSet: chosenSet).first else { return }
        bankNumber = free      // start from an empty bank, so nothing is replaced by accident
    }

    private func send() {
        guard let driveID else { return }
        let plan: SquidPlan = toPool ? .pool(subfolder: poolFolder)
            : .bank(set: chosenSet, number: bankNumber, name: bankName, replace: replace)
        busy = true
        problem = nil
        Task {
            let error = await model.sendToSquid(plan, driveID: driveID)
            busy = false
            if let error { problem = error; return }
            if case .bank(let set, _, _, _) = plan { model.selectSidebar(UsbSelection(drive: driveID, area: .set(set)).tag) }
            else { model.selectSidebar(UsbSelection(drive: driveID, area: .pool).tag) }
            dismiss()
        }
    }
}
