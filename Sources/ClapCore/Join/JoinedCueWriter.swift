import Foundation

/// Adds one start marker and a WAV region length per sound, so silence is never a separate cue set.
enum JoinedCueWriter {
    static func write(regions: [JoinedRegion], names: [String], to url: URL) throws {
        let cues = regions.map { FileCue(frame: $0.startFrame, label: names[$0.sourceIndex]) }
        try WavCueWriter.write(cues: cues, to: url, keepBackup: false)
        let original = try Data(contentsOf: url)
        var list = Data("adtl".utf8)
        for chunk in WavChunks.parse(original) where WavChunks.isList(chunk, ofType: "adtl", in: original) {
            list.append(original[chunk.dataStart + 4..<chunk.dataStart + chunk.size])
        }
        for (index, region) in regions.enumerated() {
            var text = Data()
            text.appendLE32(UInt32(index + 1))
            text.appendLE32(UInt32(region.endFrame - region.startFrame))
            text.append(contentsOf: Array("rgn ".utf8))
            text.append(contentsOf: [UInt8](repeating: 0, count: 8))
            list.append(contentsOf: Array("ltxt".utf8))
            list.appendLE32(UInt32(text.count))
            list.append(text)
        }
        var body = Data("WAVE".utf8)
        for chunk in WavChunks.parse(original) where !WavChunks.isList(chunk, ofType: "adtl", in: original) {
            body.append(original[chunk.headerStart..<min(chunk.end, original.count)])
        }
        body.append(contentsOf: Array("LIST".utf8))
        body.appendLE32(UInt32(list.count))
        body.append(list)
        guard body.count <= Int(UInt32.max) else { throw JoinError.invalidSettings }
        var data = Data("RIFF".utf8)
        data.appendLE32(UInt32(body.count))
        data.append(body)
        try data.write(to: url, options: .atomic)
        let written = try Data(contentsOf: url)
        guard CueFileReader.read(url: url) == cues,
              written == data,
              regionLengths(in: written) == regions.map({ $0.endFrame - $0.startFrame }) else {
            throw JoinError.verificationFailed
        }
    }

    static func regionLengths(in data: Data) -> [Int64] {
        var lengths: [Int64] = []
        for chunk in WavChunks.parse(data) where WavChunks.isList(chunk, ofType: "adtl", in: data) {
            var offset = chunk.dataStart + 4
            let end = chunk.dataStart + chunk.size
            while offset + 8 <= end {
                let size = Int(data.le32(offset + 4))
                guard offset + 8 + size <= end else { break }
                if String(decoding: data[offset..<offset + 4], as: UTF8.self) == "ltxt", size >= 20 {
                    lengths.append(Int64(data.le32(offset + 12)))
                }
                offset += 8 + size + (size & 1)
            }
        }
        return lengths
    }
}
