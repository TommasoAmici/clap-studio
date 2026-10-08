import Foundation

/// A place on Earth.
public struct GeoPoint: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    /// "51.5, -0.1", "51.5 -0.1" or "51.5;-0.1": latitude then longitude in decimal degrees.
    public init?(parsing text: String) {
        let numbers = text.split(whereSeparator: { ", ;\t".contains($0) }).map { Double($0) }
        guard numbers.count == 2, let lat = numbers[0], let lon = numbers[1] else { return nil }
        self.init(latitude: lat, longitude: lon)
    }

    /// The same, for showing: "51.5000, -0.1000".
    public var text: String { String(format: "%.4f, %.4f", latitude, longitude) }
}

/// A bird species heard in a recording, and where.
public struct SpeciesOccurrence: Sendable, Equatable {
    public let scientific: String
    public let common: String
    /// The most confident listening window.
    public let best: BirdDetection
    /// Stretches where it was heard, neighbouring windows merged.
    public let spans: [TimeSpan]
    /// How many 3 s windows it was heard in.
    public let windows: Int
    public var confidence: Float { best.confidence }
}

/// A field recording waiting to be listened to for birds.
public struct SpeciesJob: Sendable {
    public let id: Int64
    public let url: URL
    public let duration: Double
    public let name: String
}

/// Persistence of bird species heard in field recordings. Every candidate BirdNET produced is stored, with whether
/// the species occurs where the recording was made, so the place and the confidence cut-off can change without
/// listening again.
extension LibraryStore {
    /// Identifies what the stored rows were computed from; bump when the model or the candidate rules change.
    public static let speciesVersion = "birdnet-v2.4/1"
    /// Species heard with at least this confidence are reported (BirdNET's own default is 0.25).
    public static let reportedConfidence: Float = 0.3
    /// Two windows of one species closer than this are shown as one stretch.
    static let speciesMergeGap = 0.5

    // MARK: places

    /// Where a recording was made, if the user said.
    public func location(sampleID: Int64) -> GeoPoint? {
        let rows = (try? db.query("SELECT latitude, longitude FROM samples WHERE id = ? AND latitude IS NOT NULL",
                                  [.int(sampleID)]) { GeoPoint(latitude: $0.double(0), longitude: $0.double(1)) }) ?? []
        return rows.first.flatMap { $0 }
    }

    public func setLocation(_ point: GeoPoint?, sampleIDs: [Int64]) throws {
        try db.transaction {
            for id in sampleIDs {
                try db.run("UPDATE samples SET latitude = ?, longitude = ? WHERE id = ?",
                           [point.map { .double($0.latitude) } ?? .null, point.map { .double($0.longitude) } ?? .null, .int(id)])
            }
        }
    }

    /// The place assumed for recordings without their own.
    public var defaultLocation: GeoPoint? {
        get {
            guard let text = meta("bird_default_location") else { return nil }
            let parts = text.split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 ? GeoPoint(latitude: parts[0], longitude: parts[1]) : nil
        }
        set { try? setMeta("bird_default_location", newValue.map { "\($0.latitude),\($0.longitude)" } ?? "") }
    }

    /// The recording's own place, else the library's.
    public func effectiveLocation(sampleID: Int64) -> GeoPoint? { location(sampleID: sampleID) ?? defaultLocation }

    // MARK: listening

    /// Field recordings of the library that have not been listened to with the current settings.
    public func recordingsNeedingSpecies() -> [SpeciesJob] {
        (try? db.query("""
            SELECT s.id, r.path, s.rel_path, s.name, s.duration FROM samples s JOIN roots r ON r.id = s.root_id
            WHERE s.status = 'ok' AND r.transient = 0 AND s.duration >= ?
              AND (s.species_version IS NULL OR s.species_version != ?)
            ORDER BY s.id
            """, [.double(FieldRecording.minimumSeconds), .text(Self.speciesVersion)]) {
            SpeciesJob(id: $0.int(0), url: URL(fileURLWithPath: $0.text(1)).appendingPathComponent($0.text(2)),
                       duration: $0.double(4), name: $0.text(3))
        }) ?? []
    }

    /// Replaces a recording's candidates. `allowed` holds the scientific names that occur at its place; nil means
    /// there is no place, so nothing is ruled out.
    public func saveSpecies(sampleID: Int64, detections: [BirdDetection], allowed: Set<String>?) throws {
        try db.transaction {
            try db.run("DELETE FROM recording_species WHERE sample_id = ?", [.int(sampleID)])
            for d in detections {
                try db.run("""
                    INSERT OR REPLACE INTO recording_species(sample_id, start, end, scientific, common, confidence, allowed)
                    VALUES(?, ?, ?, ?, ?, ?, ?)
                    """, [.int(sampleID), .double(d.start), .double(d.end), .text(d.scientific), .text(d.common),
                          .double(Double(d.confidence)), .int(allowed.map { $0.contains(d.scientific) ? 1 : 0 } ?? 1)])
            }
            try db.run("UPDATE samples SET species_version = ? WHERE id = ?", [.text(Self.speciesVersion), .int(sampleID)])
        }
    }

    /// Re-applies the place to stored candidates, without listening again.
    public func refilterSpecies(sampleID: Int64, allowed: Set<String>?) throws {
        let names = try db.query("SELECT DISTINCT scientific FROM recording_species WHERE sample_id = ?",
                                 [.int(sampleID)]) { $0.text(0) }
        try db.transaction {
            for name in names {
                try db.run("UPDATE recording_species SET allowed = ? WHERE sample_id = ? AND scientific = ?",
                           [.int(allowed.map { $0.contains(name) ? 1 : 0 } ?? 1), .int(sampleID), .text(name)])
            }
        }
    }

    /// Recordings that have stored candidates.
    public func recordingsWithSpecies() -> [Int64] {
        (try? db.query("SELECT DISTINCT sample_id FROM recording_species ORDER BY sample_id") { $0.int(0) }) ?? []
    }

    // MARK: reading

    /// The species of one recording that were heard confidently and can occur at its place, most heard first.
    public func speciesOccurrences(sampleID: Int64, minimumConfidence: Float = LibraryStore.reportedConfidence)
        -> [SpeciesOccurrence] {
        let rows = (try? db.query("""
            SELECT scientific, common, start, end, confidence FROM recording_species
            WHERE sample_id = ? AND allowed = 1 AND confidence >= ? ORDER BY scientific, start
            """, [.int(sampleID), .double(Double(minimumConfidence))]) {
            BirdDetection(start: $0.double(2), end: $0.double(3), scientific: $0.text(0), common: $0.text(1),
                          confidence: Float($0.double(4)))
        }) ?? []
        var grouped: [String: [BirdDetection]] = [:]
        for row in rows { grouped[row.scientific, default: []].append(row) }
        let occurrences = grouped.values.map { windows -> SpeciesOccurrence in
            var spans: [TimeSpan] = []
            for w in windows {
                if var last = spans.last, w.start - last.end <= Self.speciesMergeGap {
                    last.end = max(last.end, w.end)
                    spans[spans.count - 1] = last
                } else {
                    spans.append(TimeSpan(start: w.start, end: w.end))
                }
            }
            return SpeciesOccurrence(scientific: windows[0].scientific, common: windows[0].common,
                                     best: windows.max { $0.confidence < $1.confidence }!, spans: spans,
                                     windows: windows.count)
        }
        return occurrences.sorted { ($0.windows, $0.confidence, $1.common) > ($1.windows, $1.confidence, $0.common) }
    }

    /// Every species heard in the library's field recordings, with the number of recordings, for the sidebar.
    public func speciesCounts(minimumConfidence: Float = LibraryStore.reportedConfidence) -> [(common: String, recordings: Int)] {
        (try? db.query("""
            SELECT common, COUNT(DISTINCT sample_id) FROM recording_species b
            JOIN samples s ON s.id = b.sample_id JOIN roots r ON r.id = s.root_id
            WHERE b.allowed = 1 AND b.confidence >= ? AND r.transient = 0 AND s.status = 'ok'
            GROUP BY common ORDER BY COUNT(DISTINCT sample_id) DESC, common
            """, [.double(Double(minimumConfidence))]) { ($0.text(0), Int($0.int(1))) }) ?? []
    }
}
