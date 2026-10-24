import Foundation

/// Checks both ZIP directories before extraction; release bundles contain ordinary files and folders only.
public enum ReleaseArchive {
    public static func validate(_ archive: URL) throws {
        let file = try FileHandle(forReadingFrom: archive)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size >= 22, size < UInt64(UInt32.max) else { throw ReleaseInstallError.invalidArchive }
        let tailSize = min(size, 65_557)
        try file.seek(toOffset: size - tailSize)
        let tail = [UInt8](try file.read(upToCount: Int(tailSize)) ?? Data())
        guard tail.count == Int(tailSize) else { throw ReleaseInstallError.invalidArchive }
        guard let end = (0...(tail.count - 22)).reversed().first(where: {
            number(tail, $0, 4) == 0x06054b50 && $0 + 22 + Int(number(tail, $0 + 20, 2)) == tail.count
        }) else { throw ReleaseInstallError.invalidArchive }
        let entries = Int(number(tail, end + 10, 2))
        let directorySize = Int(number(tail, end + 12, 4))
        let directoryOffset = UInt64(number(tail, end + 16, 4))
        guard number(tail, end + 4, 2) == 0, number(tail, end + 6, 2) == 0,
              Int(number(tail, end + 8, 2)) == entries,
              entries > 0, entries < 65_535, directorySize <= 64 * 1_048_576,
              directoryOffset + UInt64(directorySize) == size - tailSize + UInt64(end) else {
            throw ReleaseInstallError.invalidArchive
        }
        try file.seek(toOffset: directoryOffset)
        let directory = [UInt8](try file.read(upToCount: directorySize) ?? Data())
        guard directory.count == directorySize else { throw ReleaseInstallError.invalidArchive }
        var cursor = 0
        var paths = Set<String>()
        var expandedSize: UInt64 = 0
        var nextOffset: UInt64 = 0
        for _ in 0..<entries {
            try Task.checkCancellation()
            guard cursor + 46 <= directory.count, number(directory, cursor, 4) == 0x02014b50 else {
                throw ReleaseInstallError.invalidArchive
            }
            let nameLength = Int(number(directory, cursor + 28, 2))
            let extraLength = Int(number(directory, cursor + 30, 2))
            let commentLength = Int(number(directory, cursor + 32, 2))
            expandedSize += UInt64(number(directory, cursor + 24, 4))
            guard expandedSize < UInt64(UInt32.max) else { throw ReleaseInstallError.invalidArchive }
            let recordEnd = cursor + 46 + nameLength + extraLength + commentLength
            guard recordEnd <= directory.count else { throw ReleaseInstallError.invalidArchive }
            let nameBytes = Array(directory[(cursor + 46)..<(cursor + 46 + nameLength)])
            guard let path = String(bytes: nameBytes, encoding: .utf8), validPath(path),
                  paths.insert(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased().precomposedStringWithCanonicalMapping).inserted else {
                throw ReleaseInstallError.invalidArchive
            }
            let centralExtra = Array(directory[(cursor + 46 + nameLength)..<(cursor + 46 + nameLength + extraLength)])
            try validateExtra(centralExtra, local: false)
            let mode = (number(directory, cursor + 38, 4) >> 16) & 0xf000
            guard mode == 0 || mode == 0x8000 || mode == 0x4000,
                  number(directory, cursor + 8, 2) & 1 == 0,
                  number(directory, cursor + 34, 2) == 0 else { throw ReleaseInstallError.invalidArchive }
            let offset = UInt64(number(directory, cursor + 42, 4))
            let compressedSize = UInt64(number(directory, cursor + 20, 4))
            guard offset == nextOffset, offset + 30 < directoryOffset, compressedSize < UInt64(UInt32.max) else {
                throw ReleaseInstallError.invalidArchive
            }
            try file.seek(toOffset: offset)
            let local = [UInt8](try file.read(upToCount: 30) ?? Data())
            guard local.count == 30, number(local, 0, 4) == 0x04034b50,
                  number(local, 6, 2) == number(directory, cursor + 8, 2),
                  number(local, 8, 2) == number(directory, cursor + 10, 2),
                  Int(number(local, 26, 2)) == nameLength else { throw ReleaseInstallError.invalidArchive }
            if number(local, 6, 2) & 8 == 0 {
                guard number(local, 14, 4) == number(directory, cursor + 16, 4),
                      number(local, 18, 4) == number(directory, cursor + 20, 4),
                      number(local, 22, 4) == number(directory, cursor + 24, 4) else {
                    throw ReleaseInstallError.invalidArchive
                }
            }
            let localName = [UInt8](try file.read(upToCount: nameLength) ?? Data())
            guard localName == nameBytes,
                  offset + 30 + UInt64(nameLength) + UInt64(number(local, 28, 2)) + compressedSize <= directoryOffset else {
                throw ReleaseInstallError.invalidArchive
            }
            let localExtraLength = Int(number(local, 28, 2))
            let localExtra = [UInt8](try file.read(upToCount: localExtraLength) ?? Data())
            guard localExtra.count == localExtraLength else { throw ReleaseInstallError.invalidArchive }
            try validateExtra(localExtra, local: true)
            nextOffset = offset + 30 + UInt64(nameLength + localExtraLength) + compressedSize
            if number(local, 6, 2) & 8 != 0 {
                guard nextOffset + 16 <= directoryOffset else { throw ReleaseInstallError.invalidArchive }
                try file.seek(toOffset: nextOffset)
                let descriptor = [UInt8](try file.read(upToCount: 16) ?? Data())
                guard descriptor.count == 16, number(descriptor, 0, 4) == 0x08074b50,
                      number(descriptor, 4, 4) == number(directory, cursor + 16, 4),
                      number(descriptor, 8, 4) == number(directory, cursor + 20, 4),
                      number(descriptor, 12, 4) == number(directory, cursor + 24, 4) else {
                    throw ReleaseInstallError.invalidArchive
                }
                nextOffset += 16
            }
            cursor = recordEnd
        }
        guard cursor == directory.count, nextOffset == directoryOffset else { throw ReleaseInstallError.invalidArchive }
    }

    private static func validateExtra(_ bytes: [UInt8], local: Bool) throws {
        var cursor = 0
        var seen = false
        while cursor < bytes.count {
            guard cursor + 4 <= bytes.count else { throw ReleaseInstallError.invalidArchive }
            let tag = number(bytes, cursor, 2)
            let length = Int(number(bytes, cursor + 2, 2))
            // ditto writes only Unix timestamps and UID/GID; alternate paths and links are refused.
            guard !seen, tag == 0x5855, length == (local ? 12 : 8),
                  cursor + 4 + length <= bytes.count else { throw ReleaseInstallError.invalidArchive }
            seen = true
            cursor += 4 + length
        }
    }

    private static func validPath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.first == "ClapStudio.app" || pieces.first == "__MACOSX",
              pieces.dropLast().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let last = pieces.last, last != ".", last != ".." else { return false }
        return true
    }

    private static func number(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<count { value |= UInt32(bytes[offset + index]) << (index * 8) }
        return value
    }
}
