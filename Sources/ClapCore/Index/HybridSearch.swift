import Foundation

/// Combines file-name matching with semantic (CLAP) similarity for the single search box.
public enum HybridSearch {
    /// - Parameters:
    ///   - ids: candidates, already narrowed by the sidebar filters.
    ///   - nameMatches: candidates whose name or path contains the query text.
    ///   - scores: semantic similarity per sample id.
    ///   - limit: how many semantic-only results to add after the name matches.
    /// - Returns: name matches first, then the closest sounds by meaning. Within each group, best score first.
    public static func rank(ids: [Int64], nameMatches: Set<Int64>, scores: [Int64: Float], limit: Int = 200) -> [Int64] {
        func better(_ a: Int64, _ b: Int64) -> Bool { (scores[a] ?? -.infinity) > (scores[b] ?? -.infinity) }
        let named = ids.filter(nameMatches.contains).sorted(by: better)
        let semantic = ids.filter { !nameMatches.contains($0) && scores[$0] != nil }.sorted(by: better).prefix(limit)
        return named + semantic
    }
}
