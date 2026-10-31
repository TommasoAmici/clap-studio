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
    @State private var poolChoice = Self.poolRoot             // a folder of the Pool as "Breaks/707", or `newPoolFolder`
    @State private var newPoolFolder = ""                     // the name typed for a new folder
    @State private var busy = false
    @State private var problem: String?
    @State private var sameChannel = false                    // each sample goes to the same channel of the following banks
    @State private var standardChannel = 1                    // that channel
    @State private var joinFirst = false                      // join the samples (ALM Squid Salmple limits) before sending
    @State private var joinName = JoinNaming.defaultName
    @State private var pinnedBank: Int?                       // a bank the sheet was opened for ("Add Samples…" on a bank)

    private static let defaultSet = ""
    private static let newSet = "\u{1}new"
    private static let poolRoot = ""
    private static let newPoolFolderChoice = "\u{1}newfolder"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send to Squid Salmple").font(.title3.bold())
            if model.usbDrives.isEmpty {
                Text("Connect a USB stick with an ALM022 folder and it will show up here.").foregroundStyle(.secondary)
            } else {
                destination
                Divider()
                SquidExportItems(toPool: toPool, joining: joining, sameChannel: sameChannel, plan: channelPlan)
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
            Toggle("Match levels", isOn: Bindable(model).squidMatchLevels).disabled(joining)
                .help("Brings every sample to the same loudness as the app's level matching, with peaks kept below -1 dB, so they play at similar volumes.")
            Text(joining
                 ? "Joined files are 16-bit, 44.1 kHz mono with a cue marker for each sound. Trims and sound edits are applied; levels are not matched, "
                   + "so each sound keeps its own. Your library files are not changed."
                 : "Samples are converted to 16-bit, 44.1 kHz mono (what the module plays) and cut at \(Int(SquidLayout.maxSeconds)) seconds. "
                   + "Trims are applied" + (model.squidMatchLevels ? " and levels matched" : "") + ". Your library files are not changed.")
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
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: configure)
        .onChange(of: driveID) { _, _ in pickFreeBank(); keepPoolChoice() }
        .onChange(of: setChoice) { _, _ in pickFreeBank() }
        .onChange(of: bankNumber) { _, _ in replace = false }
        .onChange(of: sameChannel) { _, _ in replace = false }
        .onChange(of: joinFirst) { _, _ in replace = false }
        .onChange(of: toPool) { _, _ in replace = false }
    }

    // MARK: destination

    private var drive: UsbDrive? { driveID.flatMap { model.drive(id: $0) } }
    private var contents: SquidStickContents { driveID.flatMap { model.usbContents[$0] } ?? SquidStickContents() }
    /// The set as typed or as it is on the stick: names are never changed for the user.
    private var chosenSet: String? { setChoice == Self.defaultSet ? nil : (setChoice == Self.newSet ? newSetName : setChoice) }
    private var setReport: SquidNameReport { SquidLayout.check(setName: newSetName, existing: contents.sets.compactMap(\.name)) }
    /// Adding to the free channels of a bank that is already there, rather than writing a new bank or replacing one.
    private var adding: Bool { !toPool && !followingBanks && existingBank != nil && !replace }
    /// Samples go to one channel of consecutive banks, either one each or as joined files.
    private var followingBanks: Bool { sameChannel || joining }
    private var joining: Bool { joinFirst && !toPool }
    /// The banks already on the stick in the chosen set, with the channels that hold a sample.
    private var filledBanks: [Int: Set<Int>] {
        Dictionary(uniqueKeysWithValues: (contents.set(named: chosenSet)?.banks ?? []).map { ($0.number, $0.filled) })
    }
    /// Which bank and channel each sample goes to; see `SquidChannelPlan`.
    private var channelPlan: SquidChannelPlan {
        // Joined files are not known until joining is done, so the plan holds the estimated number of them.
        let overrides: [Int?] = joining ? Array(repeating: nil, count: model.squidJoinEstimate()) : model.squidItems.map { model.squidChannels[$0] }
        return SquidChannelPlan.make(overrides: overrides, rule: followingBanks ? .sameChannel(standardChannel) : .fillBank,
                                     startBank: bankNumber, filled: filledBanks, replacingStartBank: replace && !followingBanks)
    }
    private var existingBank: SquidBank? { contents.set(named: chosenSet)?.banks.first { $0.number == bankNumber } }
    private var tooManySets: Bool { setChoice == Self.newSet && contents.namedSetCount >= SquidLayout.maxSets }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Drive", selection: Binding(get: { driveID }, set: { driveID = $0; pinnedBank = nil })) {
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
                poolFields
            } else {
                bankFields
            }
        }
    }

    private var poolFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Folder", selection: $poolChoice) {
                Text("Pool (no folder)").tag(Self.poolRoot)
                if !contents.poolFolderPaths.isEmpty { Divider() }
                ForEach(contents.poolFolderPaths, id: \.self) { path in
                    Text(path.joined(separator: " / ")).tag(path.joined(separator: "/"))
                }
                Divider()
                Text("New folder…").tag(Self.newPoolFolderChoice)
            }
            if poolChoice == Self.newPoolFolderChoice {
                TextField("New folder name", text: $newPoolFolder).textFieldStyle(.roundedBorder)
                Text(newPoolFolderNote).font(.caption).foregroundStyle(.secondary)
            }
            Text("The Pool holds loose samples the module can load into any channel. Up to \(SquidLayout.maxEntriesPerFolder) entries per folder.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// What typing in the new folder field will do: where the folder goes, or that it is already there.
    private var newPoolFolderNote: String {
        let parts = SquidLayout.poolPath(from: newPoolFolder)
        guard !parts.isEmpty else { return "Type a name. Put a / between names to make a folder inside another one." }
        let typed = newPoolFolder.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if contents.poolFolder(at: typed) != nil { return "Pool/\(typed.joined(separator: "/")) is already on the stick. Samples are added to it." }
        return "Made as Pool/\(parts.joined(separator: "/")) (letters, numbers, spaces, - and _ only, as the stick needs)."
    }

    /// The folder the samples go to, as a path inside the Pool ("" for the Pool itself).
    private var poolSubfolder: String {
        poolChoice == Self.newPoolFolderChoice ? SquidLayout.poolPath(from: newPoolFolder).joined(separator: "/") : poolChoice
    }

    /// A folder picked on one drive is not offered on another that does not have it.
    private func keepPoolChoice() {
        guard poolChoice != Self.poolRoot, poolChoice != Self.newPoolFolderChoice else { return }
        if contents.poolFolder(at: poolChoice.split(separator: "/").map(String.init)) == nil { poolChoice = Self.poolRoot }
    }

    private var bankFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Set", selection: Binding(get: { setChoice }, set: { setChoice = $0; pinnedBank = nil })) {
                Text("Default").tag(Self.defaultSet)
                ForEach(contents.sets.compactMap(\.name), id: \.self) { Text($0).tag($0) }
                Text("New set…").tag(Self.newSet)
            }
            if setChoice == Self.newSet {
                HStack {
                    TextField("Set name", text: $newSetName).textFieldStyle(.roundedBorder)
                    if !newSetName.isEmpty { NameIssueIcon(report: setReport) }
                }
                if tooManySets {
                    Text("The module reads at most \(SquidLayout.maxSets) sets.").font(.caption).foregroundStyle(.red)
                }
            }
            if !joinFirst {
                Toggle("Same channel in following banks", isOn: $sameChannel)
                    .help("Each sample goes to the same channel of the next bank: four snares on channel 2 of banks 1 to 4.")
            }
            Toggle("Join samples before sending", isOn: $joinFirst)
                .help("Joins the samples into as few files as possible (mono, 11 seconds at most, 0.25 seconds of silence, 64 cue sets), "
                      + "one file per bank, all on the same channel. Your library files are not changed.")
            if joining {
                HStack {
                    Text("File name")
                    TextField("File name", text: $joinName, prompt: Text(JoinNaming.defaultName)).textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }
            }
            if followingBanks {
                Picker("Channel", selection: $standardChannel) {
                    ForEach(1...SquidLayout.slotsPerBank, id: \.self) { Text("Channel \($0)").tag($0) }
                }
            }
            HStack {
                Picker(followingBanks ? "Start at" : "Bank", selection: $bankNumber) {
                    ForEach(1...SquidLayout.maxBanksPerSet, id: \.self) { n in
                        let used = contents.set(named: chosenSet)?.banks.first { $0.number == n }
                        Text(used.map { "Bank \(n) (\($0.name.isEmpty ? "unnamed" : $0.name), \($0.freeSlots) free)" } ?? "Bank \(n)").tag(n)
                    }
                }
                if adding || (followingBanks && existingBank != nil) {
                    Text(existingBank?.name.isEmpty == false ? existingBank!.name : "Unnamed bank").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(followingBanks ? "Name for new banks" : "Bank name", text: $bankName).textFieldStyle(.roundedBorder)
                    NameIssueIcon(report: SquidLayout.check(bankName: bankName))
                }
            }
            if !followingBanks, let existing = existingBank {
                if existing.freeSlots > 0 {
                    Picker("This bank exists", selection: $replace) {
                        Text("Add to its \(existing.freeSlots) free channel\(existing.freeSlots == 1 ? "" : "s")").tag(false)
                        Text("Replace it").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                if replace || existing.freeSlots == 0 {
                    Toggle("Replace the existing bank (it is moved to the Trash)", isOn: $replace).font(.caption)
                }
            }
        }
    }

    // MARK: actions

    private var canSend: Bool {
        guard !busy, drive != nil, !model.squidItems.isEmpty else { return false }
        if toPool { return poolChoice != Self.newPoolFolderChoice || !SquidLayout.poolPath(from: newPoolFolder).isEmpty }
        if setChoice == Self.newSet && (setReport.isBlocked || tooManySets) { return false }
        if channelPlan.isBlocked || !channelPlan.slots.contains(where: { $0 != nil }) { return false }
        guard !followingBanks, let existing = existingBank else { return true }
        return replace || existing.freeSlots > 0
    }

    private func configure() {
        let target = model.squidTarget
        driveID = target.drive ?? model.usbDrives.first?.id
        toPool = target.pool
        // Where samples went last time is chosen again when that folder is still there; a name that is not there yet is typed in again.
        let typed = target.poolFolder.split(separator: "/").map(String.init)
        if typed.isEmpty { poolChoice = Self.poolRoot }
        else if let existing = contents.poolFolder(at: typed) { poolChoice = existing.path.joined(separator: "/") }
        else { poolChoice = Self.newPoolFolderChoice; newPoolFolder = typed.joined(separator: "/") }
        setChoice = target.set ?? Self.defaultSet
        pinnedBank = target.bank
        pickFreeBank()
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let same = env["CLAP_SNAPSHOT_SEND_SAME"].flatMap(Int.init) { sameChannel = true; standardChannel = same }
        if env["CLAP_SNAPSHOT_SEND_JOIN"] == "1" { joinFirst = true }
        #endif
    }

    private func existingBank(number: Int) -> SquidBank? { contents.set(named: chosenSet)?.banks.first { $0.number == number } }

    private func pickFreeBank() {
        replace = false
        // A bank the sheet was opened for, or the one used last, if it can take more samples.
        if let pinned = pinnedBank, (existingBank(number: pinned)?.freeSlots ?? 0) > 0 { bankNumber = pinned; return }
        guard existingBank != nil, let free = contents.freeBankNumbers(inSet: chosenSet).first else { return }
        bankNumber = free      // start from an empty bank, so nothing is replaced by accident
    }

    private func send() {
        guard let driveID else { return }
        let plan: SquidPlan = toPool ? .pool(subfolder: poolSubfolder)
            : (joining ? .joined(set: chosenSet, firstBank: bankNumber, channel: standardChannel, bankName: bankName, name: joinName)
                       : .banks(set: chosenSet, firstBank: bankNumber, bankName: bankName, slots: channelPlan.slots,
                                replace: replace && !sameChannel, overwrite: sameChannel))
        busy = true
        problem = nil
        Task {
            let error = await model.sendToSquid(plan, driveID: driveID)
            busy = false
            if let error { problem = error; return }
            model.rememberSquidDestination(plan, driveID: driveID)
            dismiss()
        }
    }
}
