import Foundation

/// Versioned schema migrations (PRAGMA user_version).
enum Schema {
    static let currentVersion = 12

    static func migrate(_ db: SQLiteDB) throws {
        let version = Int(try db.scalarInt("PRAGMA user_version") ?? 0)
        if version < 1 { try v1(db) }
        if version < 2 { try v2(db) }
        if version < 3 { try v3(db) }
        if version < 4 { try v4(db) }
        if version < 5 { try v5(db) }
        if version < 6 { try v6(db) }
        if version < 7 { try v7(db) }
        if version < 8 { try v8(db) }
        if version < 9 { try v9(db) }
        if version < 10 { try v10(db) }
        if version < 11 { try v11(db) }
        if version < 12 { try v12(db) }
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

    /// Temporary roots (a USB stick): analysed like any folder, but kept out of the library views and
    /// the similarity map, and removed again when the stick is unplugged or the app starts.
    private static func v5(_ db: SQLiteDB) throws {
        try db.exec("ALTER TABLE roots ADD COLUMN transient INTEGER NOT NULL DEFAULT 0")
    }

    /// Moods: several per sample, with how far each stands out in the library (z-score).
    private static func v6(_ db: SQLiteDB) throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS sample_moods(
            sample_id INTEGER NOT NULL, mood TEXT NOT NULL, z REAL NOT NULL,
            PRIMARY KEY(sample_id, mood));
        CREATE INDEX IF NOT EXISTS sample_moods_mood ON sample_moods(mood);
        """)
    }

    /// Field recordings: the audible segments of a long file, each with its own embedding. The sample's own
    /// embedding is the composite of these. `segment_version` records which segmenter produced them.
    private static func v7(_ db: SQLiteDB) throws {
        try db.exec("ALTER TABLE samples ADD COLUMN segment_version INTEGER NOT NULL DEFAULT 0")
        try db.exec("""
        CREATE TABLE IF NOT EXISTS sample_segments(
            sample_id INTEGER NOT NULL, idx INTEGER NOT NULL,
            start REAL NOT NULL, end REAL NOT NULL, embedding BLOB NOT NULL,
            PRIMARY KEY(sample_id, idx));
        """)
    }

    /// What each segment of a field recording sounds like (birds, water, ...), up to two labels per segment.
    private static func v8(_ db: SQLiteDB) throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS segment_sounds(
            sample_id INTEGER NOT NULL, idx INTEGER NOT NULL, sound TEXT NOT NULL, score REAL NOT NULL,
            PRIMARY KEY(sample_id, idx, sound));
        CREATE INDEX IF NOT EXISTS segment_sounds_sound ON segment_sounds(sound);
        """)
    }

    /// The user's own moods for a sample: NULL means "automatic", an empty string "none", otherwise the moods
    /// joined with the unit separator. The automatic moods in `sample_moods` are recomputed freely and never touched.
    private static func v10(_ db: SQLiteDB) throws {
        try db.exec("ALTER TABLE samples ADD COLUMN moods_manual TEXT")
    }

    /// Whether a file has been looked at for a place it carries (0: not yet). A place the user sets counts as looked at.
    private static func v11(_ db: SQLiteDB) throws {
        try db.exec("ALTER TABLE samples ADD COLUMN location_version INTEGER NOT NULL DEFAULT 0")
    }

    /// What files say about themselves (titles, descriptions, keywords, UCS names), read from the file, never edited.
    /// `keywords` are joined with the unit separator.
    private static func v12(_ db: SQLiteDB) throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS file_meta(
            sample_id INTEGER PRIMARY KEY, title TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '',
            keywords TEXT NOT NULL DEFAULT '', category TEXT NOT NULL DEFAULT '', subcategory TEXT NOT NULL DEFAULT '',
            ucs_id TEXT NOT NULL DEFAULT '', creator TEXT NOT NULL DEFAULT '', source TEXT NOT NULL DEFAULT '',
            originator TEXT NOT NULL DEFAULT '', date TEXT NOT NULL DEFAULT '');
        """)
    }

    /// Bird species heard in field recordings. `latitude`/`longitude` are where a recording was made (optional);
    /// `species_version` records which detector settings produced its rows (NULL: not listened to yet). Every row
    /// is a candidate; `allowed` says whether the species occurs at the recording's place (always 1 without one).
    private static func v9(_ db: SQLiteDB) throws {
        try db.exec("ALTER TABLE samples ADD COLUMN latitude REAL")
        try db.exec("ALTER TABLE samples ADD COLUMN longitude REAL")
        try db.exec("ALTER TABLE samples ADD COLUMN species_version TEXT")
        try db.exec("""
        CREATE TABLE IF NOT EXISTS recording_species(
            sample_id INTEGER NOT NULL, start REAL NOT NULL, end REAL NOT NULL,
            scientific TEXT NOT NULL, common TEXT NOT NULL, confidence REAL NOT NULL,
            allowed INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY(sample_id, start, scientific));
        CREATE INDEX IF NOT EXISTS recording_species_name ON recording_species(scientific);
        """)
    }
}
