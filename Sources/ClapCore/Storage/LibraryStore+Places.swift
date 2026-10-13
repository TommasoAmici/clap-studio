import Foundation

/// Where recordings were made: the user's own choice, or what the file says, and a place for the library as a whole.
extension LibraryStore {
    /// Bump when the file readers (places, descriptive metadata) learn to find more, so files are looked at again.
    public static let locationReaderVersion = 2

    /// Where a recording was made, if known.
    public func location(sampleID: Int64) -> GeoPoint? {
        let rows = (try? db.query("SELECT latitude, longitude FROM samples WHERE id = ? AND latitude IS NOT NULL",
                                  [.int(sampleID)]) { GeoPoint(latitude: $0.double(0), longitude: $0.double(1)) }) ?? []
        return rows.first.flatMap { $0 }
    }

    /// Sets (or with nil clears) the place of samples. A place the user sets is never replaced by one read from a file.
    public func setLocation(_ point: GeoPoint?, sampleIDs: [Int64]) throws {
        try db.transaction {
            for id in sampleIDs {
                try db.run("UPDATE samples SET latitude = ?, longitude = ?, location_version = ? WHERE id = ?",
                           [point.map { .double($0.latitude) } ?? .null, point.map { .double($0.longitude) } ?? .null,
                            .int(Int64(Self.locationReaderVersion)), .int(id)])
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

    /// Every sample of the library that has a place of its own.
    public func locations() -> [Int64: GeoPoint] {
        let rows = (try? db.query("""
            SELECT s.id, s.latitude, s.longitude FROM samples s JOIN roots r ON r.id = s.root_id
            WHERE s.latitude IS NOT NULL AND s.longitude IS NOT NULL AND r.transient = 0
            """) { row in GeoPoint(latitude: row.double(1), longitude: row.double(2)).map { (row.int(0), $0) } }) ?? []
        return Dictionary(rows.compactMap { $0 }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: reading places from files

    /// Files not yet looked at for a place.
    public func locationJobs(limit: Int) -> [IndexJob] {
        (try? db.query("""
            SELECT s.id, r.path, s.rel_path FROM samples s JOIN roots r ON r.id = s.root_id
            WHERE s.status = 'ok' AND r.transient = 0 AND s.location_version < ? ORDER BY s.id LIMIT ?
            """, [.int(Int64(Self.locationReaderVersion)), .int(Int64(limit))]) {
            IndexJob(id: $0.int(0), url: URL(fileURLWithPath: $0.text(1)).appendingPathComponent($0.text(2)))
        }) ?? []
    }

    public func locationBacklog() -> Int {
        Int((try? db.scalarInt("""
            SELECT COUNT(*) FROM samples s JOIN roots r ON r.id = s.root_id
            WHERE s.status = 'ok' AND r.transient = 0 AND s.location_version < ?
            """, [.int(Int64(Self.locationReaderVersion))])) ?? 0)
    }

    /// Stores what was found in files. A sample that already has a place keeps it; every file looked at is marked done.
    /// Returns the samples that got a place.
    @discardableResult
    public func saveFileLocations(_ found: [(id: Int64, point: GeoPoint?)]) throws -> [Int64] {
        var placed: [Int64] = []
        try db.transaction {
            for item in found {
                if let point = item.point,
                   try db.scalarInt("SELECT COUNT(*) FROM samples WHERE id = ? AND latitude IS NULL", [.int(item.id)]) == 1 {
                    // A new place changes which birds can be there, so a recording is listened to again.
                    try db.run("UPDATE samples SET latitude = ?, longitude = ?, species_version = NULL WHERE id = ?",
                               [.double(point.latitude), .double(point.longitude), .int(item.id)])
                    placed.append(item.id)
                }
                try db.run("UPDATE samples SET location_version = ? WHERE id = ?", [.int(Int64(Self.locationReaderVersion)), .int(item.id)])
            }
        }
        return placed
    }
}
