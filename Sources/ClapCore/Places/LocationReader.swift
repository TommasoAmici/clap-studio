import AVFoundation
import Foundation

/// Finds where a recording was made, from what the file itself says: iXML and XMP chunks of WAV files (what field
/// recorders and editors write), and the location of MP4, M4A and QuickTime files (what phones write).
public enum LocationReader {
    public static func read(url: URL) async -> GeoPoint? {
        switch url.pathExtension.lowercased() {
        case "wav", "wave", "bwf": return readWav(url: url)
        case "m4a", "mp4", "m4v", "mov", "caf", "aac": return await readAV(url: url)
        default: return nil
        }
    }

    // MARK: WAV

    static func readWav(url: URL) -> GeoPoint? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count >= 12,
              String(decoding: data[0..<4], as: UTF8.self) == "RIFF", String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        return readWav(data)
    }

    static func readWav(_ data: Data) -> GeoPoint? {
        for chunk in WavChunks.parse(data) {
            switch chunk.id {
            case "iXML", "_PMX", "XMP ", "_pmx":
                let text = String(decoding: data[chunk.dataStart..<(chunk.dataStart + chunk.size)], as: UTF8.self)
                if let point = point(inMarkup: text) { return point }
            case "LIST":
                // INFO comments and the like sometimes carry a plain "lat, lon" or ISO 6709 text.
                guard chunk.size >= 4, String(decoding: data[chunk.dataStart..<(chunk.dataStart + 4)], as: UTF8.self) == "INFO" else { continue }
                if let point = infoLocation(data, chunk) { return point }
            default: break
            }
        }
        return nil
    }

    private static func infoLocation(_ data: Data, _ chunk: WavChunk) -> GeoPoint? {
        var o = chunk.dataStart + 4
        let end = chunk.dataStart + chunk.size
        while o + 8 <= end {
            let id = String(decoding: data[o..<(o + 4)], as: UTF8.self)
            let size = Int(data.le32(o + 4))
            guard o + 8 + size <= end else { break }
            if id == "ICMT" || id == "ISBJ" || id == "IARL" {
                let text = String(decoding: data[(o + 8)..<(o + 8 + size)].prefix { $0 != 0 }, as: UTF8.self)
                if let point = GeoParse.iso6709(text) { return point }
            }
            o += 8 + size + (size & 1)
        }
        return nil
    }

    // MARK: markup (iXML, XMP)

    /// A latitude and a longitude in XML text: elements or attributes with names such as `GPSLatitude`, `LATITUDE`,
    /// `GPS_LONGITUDE`, plus a hemisphere in `GPSLatitudeRef` / `GPSLongitudeRef` when the value has none.
    static func point(inMarkup text: String) -> GeoPoint? {
        let values = markupValues(text)
        func find(_ names: (String) -> Bool, refs: (String) -> Bool) -> Double? {
            for item in values where names(item.name) && !item.name.lowercased().hasSuffix("ref") {
                guard var degrees = GeoParse.degrees(item.value) else { continue }
                if !item.value.uppercased().contains(where: { "NSEW".contains($0) }),
                   let ref = values.first(where: { refs($0.name) })?.value.uppercased(), ref.hasPrefix("S") || ref.hasPrefix("W") {
                    degrees = -abs(degrees)
                }
                return degrees
            }
            return nil
        }
        let lat = find({ isName($0, "latitude", short: ["lat"]) }, refs: { isName($0, "latituderef", short: ["latref"]) })
        let lon = find({ isName($0, "longitude", short: ["lon", "long", "lng"]) },
                       refs: { isName($0, "longituderef", short: ["lonref", "longref"]) })
        if let lat, let lon, let point = GeoPoint(latitude: lat, longitude: lon) { return point }
        // One value for both ("GPS", "LOCATION", "COORDINATES").
        for item in values where ["gps", "location", "coordinates", "position", "geo"].contains(where: { item.name.lowercased().contains($0) }) {
            if let point = GeoParse.pair(item.value) { return point }
        }
        return nil
    }

    private static func isName(_ name: String, _ word: String, short: [String]) -> Bool {
        let lower = name.lowercased()
        if lower.contains(word) { return true }
        return lower.split(whereSeparator: { "_:-. ".contains($0) }).contains { short.contains(String($0)) }
    }

    /// Element texts and attribute values, with the name each came from (namespace prefixes kept).
    static func markupValues(_ text: String) -> [(name: String, value: String)] {
        var found: [(String, String)] = []
        for m in Rx.matches(#"<([A-Za-z0-9_:.\-]+)(?:\s[^>]*)?>\s*([^<>]{1,200}?)\s*</\1>"#, in: text) { found.append((m[1], m[2])) }
        for m in Rx.matches(#"([A-Za-z0-9_:.\-]+)\s*=\s*"([^"<>]{1,200})""#, in: text) { found.append((m[1], m[2])) }
        return found
    }

    // MARK: MP4, M4A, QuickTime

    private static func readAV(url: URL) async -> GeoPoint? {
        let asset = AVURLAsset(url: url)
        guard let formats = try? await asset.load(.availableMetadataFormats) else { return nil }
        for format in formats {
            guard let items = try? await asset.loadMetadata(for: format) else { continue }
            for item in items {
                let identifier = item.identifier?.rawValue.lowercased() ?? ""
                let key = (item.key as? String)?.lowercased() ?? ""
                guard identifier.contains("iso6709") || identifier.contains("location") || key.contains("xyz") || key.contains("location") else { continue }
                if let text = try? await item.load(.stringValue), let point = GeoParse.pair(text) { return point }
            }
        }
        return nil
    }
}
