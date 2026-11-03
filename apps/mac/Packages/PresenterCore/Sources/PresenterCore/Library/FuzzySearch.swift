import Foundation

public enum FuzzySearch {
    public static func matches(_ query: String, in text: String) -> Bool {
        score(query, in: text) != nil
    }

    public static func score(_ query: String, in text: String) -> Double? {
        let queryWords = words(query)
        let textWords = words(text)
        guard !queryWords.isEmpty, !textWords.isEmpty else { return nil }

        var total = 0.0
        var matchedAny = false

        for queryWord in queryWords {
            var best: Double?
            for textWord in textWords {
                if let wordScore = wordScore(queryWord, textWord) {
                    best = max(best ?? 0, wordScore)
                }
            }
            guard let wordBest = best else { return nil }
            matchedAny = true
            total += wordBest
        }

        guard matchedAny else { return nil }
        let completeness = Double(queryWords.count) / Double(max(queryWords.count, textWords.count))
        return total / Double(queryWords.count) + completeness
    }

    public static func combinedScore(_ query: String, name: String, content: String) -> Double? {
        let queryWords = words(query)
        let normalizedName = words(name)
        var total = 0.0
        for queryWord in queryWords {
            let nameMatches = normalizedName.compactMap {
                wordScore(queryWord, $0)
            }.max() ?? 0
            let contentMatches = words(content).compactMap {
                wordScore(queryWord, $0)
            }.max() ?? 0
            guard nameMatches > 0 || contentMatches > 0 else { return nil }
            total += max(nameMatches, contentMatches) + (nameMatches > 0 ? 0.35 : 0)
        }
        return total / Double(max(queryWords.count, 1))
    }

    private static func wordScore(_ query: String, _ candidate: String) -> Double? {
        if query == candidate {
            return 1.0
        }

        if candidate.hasPrefix(query), query.count >= 2 {
            return 0.92 - Double(query.count - candidate.count) / 100
        }

        if query.count >= 4, candidate.contains(query)
            || (candidate.count >= 3 && query.contains(candidate)) {
            return 0.86
        }

        let distance = levenshtein(query, candidate)
        let longest = max(query.count, candidate.count)
        guard longest > 0 else { return nil }
        let allowedDistance: Int
        switch longest {
        case 0...3: allowedDistance = 0
        case 4...5: allowedDistance = 1
        case 6...9: allowedDistance = 2
        case 10...15: allowedDistance = 3
        default: allowedDistance = 4
        }

        if distance > allowedDistance, hasAdjacentTransposition(query, candidate) {
            return 0.78
        }
        guard distance <= allowedDistance else {
            if isFuzzySubsequence(query, candidate) {
                return 0.72
            }
            return nil
        }
        return 0.82 - Double(distance) / Double(max(longest, 1)) * 0.3
    }

    private static func hasAdjacentTransposition(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs)
        let b = Array(rhs)
        guard a.count == b.count else { return false }
        let differences = (0..<a.count).filter { a[$0] != b[$0] }
        guard differences.count == 2, differences[1] == differences[0] + 1 else { return false }
        let first = differences[0]
        return a[first] == b[first + 1] && a[first + 1] == b[first]
    }

    private static func words(_ text: String) -> [String] {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        return normalized.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.count < b.count { return levenshtein(rhs, lhs) }
        guard !b.isEmpty else { return a.count }

        var previous = Array(0...b.count)
        for (indexA, charA) in a.enumerated() {
            var current = [indexA + 1]
            for (indexB, charB) in b.enumerated() {
                current.append(min(
                    previous[indexB + 1] + 1,
                    current[indexB] + 1,
                    previous[indexB] + (charA == charB ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous.last ?? 0
    }

    private static func isFuzzySubsequence(_ query: String, _ candidate: String) -> Bool {
        guard abs(query.count - candidate.count) <= 2 else { return false }
        let queryArray = Array(query)
        let candidateArray = Array(candidate)
        var matches = 0
        var candidateIndex = 0
        for char in queryArray {
            while candidateIndex < candidateArray.count, candidateArray[candidateIndex] != char {
                candidateIndex += 1
            }
            if candidateIndex == candidateArray.count { break }
            matches += 1
            candidateIndex += 1
        }
        return Double(matches) / Double(queryArray.count) >= 0.72
    }
}
