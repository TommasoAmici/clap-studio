import Foundation

/// Atomic writes expose auxiliary files; only published messages may be consumed.
public enum VST3LiveFiles {
    public static func isCommand(_ name: String) -> Bool {
        guard name.hasPrefix("command-"), name.hasSuffix(".json") else { return false }
        let sequence = name.dropFirst(8).dropLast(5).utf8
        return sequence.count >= 8 && sequence.allSatisfy { (48...57).contains($0) }
    }

    public static func isReply(_ name: String) -> Bool {
        guard name.hasPrefix("reply-"), name.hasSuffix(".json") else { return false }
        return UUID(uuidString: String(name.dropFirst(6).dropLast(5))) != nil
    }
}
