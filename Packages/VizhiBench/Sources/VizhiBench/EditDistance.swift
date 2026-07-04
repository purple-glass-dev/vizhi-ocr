/// Levenshtein edit distance over any sequence of equatable elements — characters for CER, tokens
/// for WER. Two-row dynamic programming: O(n·m) time, O(min(n,m)) space.
func levenshtein<Element: Equatable>(_ a: [Element], _ b: [Element]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    // Keep the shorter sequence as the inner (column) dimension to minimize the row width.
    let (s, t) = a.count <= b.count ? (a, b) : (b, a)

    var previous = Array(0...s.count)
    var current = [Int](repeating: 0, count: s.count + 1)

    for (i, tElement) in t.enumerated() {
        current[0] = i + 1
        for j in 0..<s.count {
            let cost = s[j] == tElement ? 0 : 1
            current[j + 1] = min(
                previous[j + 1] + 1,   // deletion
                current[j] + 1,        // insertion
                previous[j] + cost     // substitution
            )
        }
        swap(&previous, &current)
    }
    return previous[s.count]
}
