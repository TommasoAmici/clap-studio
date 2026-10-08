import Foundation

/// Versioned schema migrations (PRAGMA user_version).
enum Schema {
    static let currentVersion = 4

    static func migrate(_ db: SQLiteDB) throws {
        let version = Int(try db.scalarInt("PRAGMA user_version") ?? 0)
        if version < 1 { try v1(db) }
        if version < 2 { try v2(db) }
        if version < 3 { try v3(db) }
        if version < 4 { try v4(db) }
        try db.exec("PRAGMA user_version = \(currentVersion)")
    }

    private static func v1(_ db: SQLiteDB) throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS roots(
            id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, last_scan REAL);
        CREATE TABLE IF NOT EXISTS samples(
            id INTEGER PRIMARY KEY,
            root_id INTEGER NOT NULL REFERENCES roots(id),
            rel_path TEXT NOT NULL, name TEXT NOT NULL, ext TEXT NOT NULL,
            duration REAL, sample_rate REAL, channels INTEGER,
            size INTEGER NOT NULL, mtime REAL NOT NULL, fingerprint TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            error TEXT, indexed_at REAL, model_version TEXT, embedding BLOB,
            cues_dirty INTEGER NOT NULL DEFAULT 0,
            UNIQUE(root_id, rel_path));
        CREATE INDEX IF NOT EXISTS samples_fp ON samples(fingerprint);
        CREATE INDEX IF NOT EXISTS samples_status ON samples(status);
        CREATE TABLE IF NOT EXISTS projection(
            id INTEGER PRIMARY KEY CHECK(id = 1),
            model_version TEXT NOT NULL, dim INTEGER NOT NULL, k INTEGER NOT NULL,
            mean BLOB NOT NULL, components BLOB NOT NULL, sample_count INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS centroids(cluster INTEGER PRIMARY KEY, vec BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS sample_coords(
            sample_id INTEGER PRIMARY KEY REFERENCES samples(id),
            pca BLOB NOT NULL, cluster INTEGER NOT NULL, x REAL NOT NULL, y REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS usage_events(
            id INTEGER PRIMARY KEY, sample_id INTEGER NOT NULL, ts REAL NOT NULL);
        CREATE INDEX IF NOT EXISTS usage_sample ON usage_events(sample_id);
        CREATE TABLE IF NOT EXISTS cue_points(
            id INTEGER PRIMARY KEY, sample_id INTEGER NOT NULL,
            position_frames INTEGER NOT NULL, label TEXT NOT NULL DEFAULT '',
            source TEXT NOT NULL, file_synced INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX IF NOT EXISTS cue_sample ON cue_points(sample_id);
        """)
    }

    /// Descriptors, categories, favorites, hidden flag and collections.
    private static func v2(_ db: SQLiteDB) throws {
        for column in [
            "loudness REAL", "peak REAL", "crest REAL", "centroid REAL", "is_loop INTEGER",
            "bpm REAL", "bpm_conf REAL", "bpm_manual REAL", "pitch_hz REAL", "key_name TEXT",
            "desc_version INTEGER NOT NULL DEFAULT 0",
            "category TEXT", "category_conf REAL", "category_manual TEXT", "category_version TEXT",
            "favorite INTEGER NOT NULL DEFAULT 0", "hidden INTEGER NOT NULL DEFAULT 0",
        ] {
            try db.exec("ALTER TABLE samples ADD COLUMN \(column)")
        }
        try db.exec("""
        CREATE TABLE IF NOT EXISTS collections(
            id INTEGER PRIMARY KEY, name TEXT NOT NULL, created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS collection_items(
            collection_id INTEGER NOT NULL, sample_id INTEGER NOT NULL, added REAL NOT NULL,
            PRIMARY KEY(collection_id, sample_id));
        CREATE INDEX IF NOT EXISTS collection_items_sample ON collection_items(sample_id);
        """)
    }

    /// Free-text tags.
    private static func v3(_ db: SQLiteDB) throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS sample_tags(
            sample_id INTEGER NOT NULL, tag TEXT NOT NULL COLLATE NOCASE,
            PRIMARY KEY(sample_id, tag));
        CREATE INDEX IF NOT EXISTS sample_tags_tag ON sample_tags(tag);
        """)
    }

    /// Non-destructive trims: the part of a file to use. The audio file is never touched.
    private static func v4(_ db: SQLiteDB) throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS sample_trims(
            sample_id INTEGER PRIMARY KEY,
            start_seconds REAL NOT NULL, end_seconds REAL NOT NULL, fade_out REAL NOT NULL DEFAULT 0);
        """)
    }
}
