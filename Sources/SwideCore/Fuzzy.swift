import Foundation

public struct FuzzyMatch: Equatable, Sendable {
    public let score: Double
    /// Character offsets of matched characters, for highlighting.
    public let indices: [Int]
}

public enum Fuzzy {
    private static let boundaries: Set<Character> = ["-", "_", " ", ".", "/"]

    /// Substring matches win; otherwise a greedy subsequence match with
    /// bonuses for consecutive characters and word starts.
    public static func match(_ text: String, _ query: String) -> FuzzyMatch? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !q.isEmpty else { return FuzzyMatch(score: 0, indices: []) }
        let t = Array(text.lowercased())
        let lengthPenalty = Double(t.count) * 0.05

        if let start = substringStart(t, q) {
            let atBoundary = start == 0 || boundaries.contains(t[start - 1])
            var score = Double(q.count) * 3 + 5
            if atBoundary { score += 4 }
            if start == 0 { score += 3 }
            return FuzzyMatch(score: score - lengthPenalty, indices: Array(start..<(start + q.count)))
        }

        var qi = 0, score = 0.0, last = -2
        var indices: [Int] = []
        for i in t.indices where qi < q.count {
            guard t[i] == q[qi] else { continue }
            var s = 1.0
            if i == last + 1 { s += 2 }
            if i == 0 || boundaries.contains(t[i - 1]) { s += 2 }
            score += s
            indices.append(i)
            last = i
            qi += 1
        }
        guard qi == q.count else { return nil }
        return FuzzyMatch(score: score - lengthPenalty, indices: indices)
    }

    private static func substringStart(_ t: [Character], _ q: [Character]) -> Int? {
        guard q.count <= t.count else { return nil }
        for i in 0...(t.count - q.count) where t[i] == q[0] {
            if Array(t[i..<(i + q.count)]) == q { return i }
        }
        return nil
    }
}

/// Stable across launches, unlike `String.hashValue`.
public func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    // FNV's low bits are weak; mix so `% 360` spreads hues.
    h ^= h >> 33
    h = h &* 0xff51afd7ed558ccd
    h ^= h >> 33
    return h
}

/// Hue in 0..<1 used for a project's monogram color.
public func stableHue(_ s: String) -> Double {
    Double(stableHash(s) % 360) / 360
}

public func monogram(_ name: String) -> String {
    let parts = name.split(whereSeparator: { "-_ .".contains($0) })
    let letters = parts.count > 1 ? [parts[0].first, parts[1].first] : Array(name.prefix(2)).map { Optional($0) }
    return String(letters.compactMap { $0 }).uppercased()
}
