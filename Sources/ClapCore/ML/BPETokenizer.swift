import Foundation

/// RoBERTa-style byte-level BPE tokenizer (the one LAION-CLAP's text encoder uses).
/// Matches Hugging Face `RobertaTokenizer` with `add_prefix_space=False`.
public final class BPETokenizer: @unchecked Sendable {
    public static let bos = 0, pad = 1, eos = 2

    private let vocab: [String: Int]
    private let ranks: [String: Int]               // "a b" -> merge priority
    private let byteToChar: [UInt8: Character]
    private let pattern: NSRegularExpression
    private let lock = NSLock()
    private var cache: [String: [String]] = [:]

    public init(vocab: [String: Int], merges: [String]) {
        self.vocab = vocab
        var ranks: [String: Int] = [:]
        for (i, m) in merges.enumerated() { ranks[m] = i }
        self.ranks = ranks
        self.byteToChar = Self.byteMap()
        // GPT-2 pre-tokenisation pattern.
        self.pattern = try! NSRegularExpression(
            pattern: #"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+"#)
    }

    public convenience init(vocabURL: URL, mergesURL: URL) throws {
        let vocabData = try Data(contentsOf: vocabURL)
        guard let vocab = try JSONSerialization.jsonObject(with: vocabData) as? [String: Int] else {
            throw ModelLoadError.failed("invalid tokenizer vocabulary")
        }
        let lines = try String(contentsOf: mergesURL, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: true)
        let merges = lines.filter { !$0.hasPrefix("#version") }.map(String.init)
        self.init(vocab: vocab, merges: merges)
    }

    /// `<s> tokens </s>` padded with `<pad>` (or truncated) to exactly `length` ids, plus the attention mask.
    public func encode(_ text: String, length: Int) -> (ids: [Int32], mask: [Int32]) {
        var ids = [Self.bos] + tokenize(text).prefix(max(0, length - 2)) + [Self.eos]
        let real = ids.count
        ids += [Int](repeating: Self.pad, count: length - real)
        return (ids.map(Int32.init), (0..<length).map { $0 < real ? 1 : 0 })
    }

    public func tokenize(_ text: String) -> [Int] {
        let ns = text as NSString
        var out: [Int] = []
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let piece = ns.substring(with: match.range)
            let mapped = String(piece.utf8.map { byteToChar[$0]! })
            for token in bpe(mapped) {
                if let id = vocab[token] { out.append(id) }
            }
        }
        return out
    }

    private func bpe(_ word: String) -> [String] {
        lock.lock()
        if let hit = cache[word] { lock.unlock(); return hit }
        lock.unlock()

        var parts = word.map(String.init)
        while parts.count > 1 {
            var best: (rank: Int, index: Int)?
            for i in 0..<(parts.count - 1) {
                if let r = ranks[parts[i] + " " + parts[i + 1]], r < (best?.rank ?? Int.max) { best = (r, i) }
            }
            guard let (_, at) = best else { break }
            let first = parts[at], second = parts[at + 1]
            var merged: [String] = []
            var i = 0
            while i < parts.count {
                if i < parts.count - 1, parts[i] == first, parts[i + 1] == second {
                    merged.append(first + second); i += 2
                } else {
                    merged.append(parts[i]); i += 1
                }
            }
            parts = merged
        }
        lock.lock(); cache[word] = parts; lock.unlock()
        return parts
    }

    /// GPT-2 `bytes_to_unicode`: printable bytes map to themselves, the rest to U+0100 and up.
    private static func byteMap() -> [UInt8: Character] {
        var printable = Array(33...126) + Array(161...172) + Array(174...255)
        var chars = printable
        var n = 0
        for b in 0..<256 where !printable.contains(b) {
            printable.append(b)
            chars.append(256 + n)
            n += 1
        }
        var map: [UInt8: Character] = [:]
        for (b, c) in zip(printable, chars) { map[UInt8(b)] = Character(UnicodeScalar(c)!) }
        return map
    }
}
