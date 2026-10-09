import Foundation

/// What is wrong, if anything, with a set or bank name. Names are never changed to fit the rules: they are kept as typed
/// (or as the stick has them), and this says what the module may do with them.
public struct SquidNameReport: Equatable, Sendable {
    /// The module may not read the name as written, but it can still be saved.
    public var warnings: [String] = []
    /// A folder cannot have this name, so it cannot be saved.
    public var blockers: [String] = []
    public var rule: String

    public var isBlocked: Bool { !blockers.isEmpty }
    public var isClean: Bool { warnings.isEmpty && blockers.isEmpty }

    /// For a tooltip: what the problem is, then the rule.
    public var message: String {
        let problems = blockers + warnings
        return problems.isEmpty ? rule : problems.joined(separator: "\n") + "\n\n" + rule
    }
}

extension SquidLayout {
    /// Characters FAT32 does not allow in a folder name.
    public static let forbiddenFolderCharacters = "\\/:*?\"<>|"

    static let setRule = "Set names: the module reads “Set ” followed by at most \(maxSetNameLength) characters, and up to \(maxSets) sets "
        + "on a stick. Folder names cannot contain \(forbiddenFolderCharacters.map(String.init).joined(separator: " ")). "
        + "Your text is kept exactly as typed."
    static let bankRule = "Bank names: the module shows the first \(maxNameLength) ASCII characters of a bank's name (its info.txt). "
        + "Your text is kept exactly as typed."

    /// `existing` are the other sets on the stick; `renaming` is the set being renamed, which may keep its own name (or change its case).
    public static func check(setName name: String, existing: [String] = [], renaming: String? = nil) -> SquidNameReport {
        var report = SquidNameReport(rule: setRule)
        if name.trimmingCharacters(in: .whitespaces).isEmpty { report.blockers.append("A set needs a name.") }
        let bad = name.filter { $0.unicodeScalars.contains { forbiddenFolderCharacters.unicodeScalars.contains($0) } }
        if !bad.isEmpty {
            report.blockers.append("A folder name cannot contain " + Set(bad).sorted().map { "“\($0)”" }.joined(separator: " ") + ".")
        }
        if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            report.blockers.append("A folder name cannot contain control characters.")
        }
        if existing.contains(where: { sameSet($0, name) && $0 != renaming }) {
            report.blockers.append("A set named “\(name)” already exists.")
        }
        if name.count > maxSetNameLength {
            report.warnings.append("“\(name)” has \(name.count) characters; the module expects at most \(maxSetNameLength).")
        }
        return report
    }

    /// The part of a bank name the module shows.
    public static func moduleShows(bankName name: String) -> String {
        let shown = name.unicodeScalars.filter { $0.isASCII && !CharacterSet.controlCharacters.contains($0) }.prefix(maxNameLength)
        return String(String.UnicodeScalarView(shown))
    }

    public static func check(bankName name: String) -> SquidNameReport {
        var report = SquidNameReport(rule: bankRule)
        let shown = moduleShows(bankName: name)
        if shown != name {
            if name.count > maxNameLength { report.warnings.append("“\(name)” has \(name.count) characters; the module shows \(maxNameLength).") }
            if name.unicodeScalars.contains(where: { !$0.isASCII }) { report.warnings.append("The module can only show plain ASCII characters.") }
            report.warnings.append("It will show “\(shown)”.")
        }
        return report
    }
}
