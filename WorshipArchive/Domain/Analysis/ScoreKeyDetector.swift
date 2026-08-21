import Foundation

nonisolated struct ScoreKeyCandidate: Equatable, Sendable {
    let musicalKey: MusicalKey
    let confidence: Double
}

/// Finds only the tonal center (C...B). Major/minor quality is intentionally
/// ignored because the import flow stores a practical performance key.
nonisolated struct ScoreKeyDetector: Sendable {
    func detect(in text: String) -> ScoreKeyCandidate? {
        let roots = text
            .components(separatedBy: .whitespacesAndNewlines)
            .compactMap(parseChordRoot)
        guard roots.count >= 3, let last = roots.last else {
            return nil
        }

        let counts = Dictionary(grouping: roots, by: { $0 }).mapValues(\.count)
        let firstIndexes = Dictionary(uniqueKeysWithValues: Set(roots).map { root in
            (root, roots.firstIndex(of: root) ?? .max)
        })
        let ranked = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return firstIndexes[lhs.key, default: .max]
                < firstIndexes[rhs.key, default: .max]
        }
        guard let best = ranked.first else { return nil }
        let runnerUpCount = ranked.dropFirst().first?.value ?? 0
        let margin = best.value - runnerUpCount
        let occurrenceCount = best.value
        guard occurrenceCount >= 2 else { return nil }
        guard best.key == last || margin >= 3 else { return nil }
        guard let musicalKey = musicalKey(for: best.key) else { return nil }

        let confidence = min(
            0.95,
            max(0.65, 0.62 + Double(occurrenceCount) / Double(roots.count) * 0.2
                + min(Double(margin) / 12, 0.12))
        )
        return ScoreKeyCandidate(musicalKey: musicalKey, confidence: confidence)
    }

    private func parseChordRoot(_ rawToken: String) -> Int? {
        var token = rawToken.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"'`,.:;[]{}<>|()")
        )
        token = token
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "¾", with: "#")
        guard let first = token.first, ("A"..."G").contains(String(first)) else {
            return nil
        }

        if token.count > 2 {
            let second = token.index(after: token.startIndex)
            let third = token.index(after: second)
            if token[second] == "t", token[third].lowercased() == "m" {
                token.replaceSubrange(second...second, with: "#")
            }
        }

        var rootLength = 1
        if token.count > 1 {
            let accidental = token[token.index(after: token.startIndex)]
            if accidental == "#" || accidental == "b" { rootLength += 1 }
        }
        let root = String(token.prefix(rootLength))
        let suffix = token.dropFirst(rootLength).split(separator: "/", maxSplits: 1).first ?? ""
        let normalizedSuffix = suffix.lowercased().replacingOccurrences(of: "?", with: "7")
        let allowedSuffixes: Set<String> = [
            "", "m", "min", "maj", "major", "minor", "dim", "aug",
            "sus", "sus2", "sus4", "add", "add9", "2", "4", "5", "6",
            "7", "9", "11", "13", "m6", "m7", "m9", "m11", "maj7",
            "maj9", "mmaj7", "dim7", "7sus4", "7sus2"
        ]
        guard allowedSuffixes.contains(normalizedSuffix) else { return nil }

        return switch root {
        case "C": 0
        case "C#", "Db": 1
        case "D": 2
        case "D#", "Eb": 3
        case "E": 4
        case "F": 5
        case "F#", "Gb": 6
        case "G": 7
        case "G#", "Ab": 8
        case "A": 9
        case "A#", "Bb": 10
        case "B": 11
        default: nil
        }
    }

    private func musicalKey(for pitchClass: Int) -> MusicalKey? {
        return switch pitchClass {
        case 0: .cMajor
        case 1: .cSharpMajor
        case 2: .dMajor
        case 3: .eFlatMajor
        case 4: .eMajor
        case 5: .fMajor
        case 6: .fSharpMajor
        case 7: .gMajor
        case 8: .aFlatMajor
        case 9: .aMajor
        case 10: .bFlatMajor
        case 11: .bMajor
        default: nil
        }
    }
}
