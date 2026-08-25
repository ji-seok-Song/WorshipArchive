import Foundation

nonisolated struct SongDraftSuggester: Sendable {
    let minimumConfidence: Double

    init(minimumConfidence: Double = 0.65) {
        self.minimumConfidence = minimumConfidence
    }

    func suggest(
        pages: [AnalyzedPage],
        originalFileName: String,
        documentPageCount: Int
    ) -> [SongDraftSuggestion] {
        guard documentPageCount > 0 else { return [] }

        let recurringMarks = recurringShortLatinMarks(in: pages)
        var starts: [(pageIndex: Int, title: String, confidence: Double)] = []
        var previousComparableTitle: String?

        for page in pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            guard (0..<documentPageCount).contains(page.pageIndex) else { continue }
            guard let candidate = page.titleCandidate else { continue }
            guard candidate.confidence >= minimumConfidence else { continue }

            let title = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = SearchTextNormalizer.normalize(title)
            let comparableTitle = comparableTitle(normalizedTitle)
            guard !normalizedTitle.isEmpty else { continue }
            guard !comparableTitle.isEmpty else { continue }
            guard !recurringMarks.contains(comparableTitle) else { continue }
            guard previousComparableTitle.map({
                !looksLikeSameTitle(comparableTitle, $0)
            }) ?? true else {
                continue
            }

            starts.append((
                pageIndex: page.pageIndex,
                title: title,
                confidence: min(max(candidate.confidence, 0), 1)
            ))
            previousComparableTitle = comparableTitle
        }

        guard !starts.isEmpty else {
            return [fallbackSuggestion(
                originalFileName: originalFileName,
                documentPageCount: documentPageCount
            )]
        }

        return starts.indices.map { index in
            let start = starts[index]
            let nextStartPageIndex = index + 1 < starts.count
                ? starts[index + 1].pageIndex
                : documentPageCount

            return SongDraftSuggestion(
                title: start.title,
                startPageNumber: start.pageIndex + 1,
                endPageNumber: max(start.pageIndex + 1, nextStartPageIndex),
                confidence: start.confidence
            )
        }
    }

    private func recurringShortLatinMarks(in pages: [AnalyzedPage]) -> Set<String> {
        let candidates = pages.compactMap { page -> (normalized: String, original: String)? in
            guard let title = page.titleCandidate?.text else { return nil }
            let normalized = comparableTitle(
                strippingTrailingPageNumber(from: SearchTextNormalizer.normalize(title))
            )
            guard !normalized.isEmpty else { return nil }
            return (normalized, title)
        }
        let counts = Dictionary(grouping: candidates, by: \.normalized)
            .mapValues(\.count)

        return Set(candidates.compactMap { candidate in
            guard counts[candidate.normalized, default: 0] >= 2 else { return nil }
            let compact = candidate.original.filter(\.isLetter)
            guard (2...16).contains(compact.count) else { return nil }
            guard compact.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
            guard compact == compact.uppercased() else { return nil }
            return candidate.normalized
        })
    }

    private func strippingTrailingPageNumber(from value: String) -> String {
        var characters = Array(value)
        while characters.last?.isNumber == true {
            characters.removeLast()
        }
        return String(characters)
    }

    private func comparableTitle(_ value: String) -> String {
        strippingTrailingPageNumber(from: value)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func looksLikeSameTitle(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs { return true }

        let shorterCount = min(lhs.count, rhs.count)
        let longerCount = max(lhs.count, rhs.count)
        if shorterCount >= 5,
           abs(lhs.count - rhs.count) <= 2,
           (lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)) {
            return true
        }

        guard shorterCount >= 6, longerCount - shorterCount <= 3 else {
            return false
        }
        let distance = editDistance(Array(lhs), Array(rhs))
        let similarity = 1 - Double(distance) / Double(longerCount)
        return similarity >= 0.82
    }

    private func editDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        for (lhsIndex, lhsCharacter) in lhs.enumerated() {
            var current = Array(repeating: 0, count: rhs.count + 1)
            current[0] = lhsIndex + 1
            for (rhsIndex, rhsCharacter) in rhs.enumerated() {
                current[rhsIndex + 1] = min(
                    current[rhsIndex] + 1,
                    previous[rhsIndex + 1] + 1,
                    previous[rhsIndex] + (lhsCharacter == rhsCharacter ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private func fallbackSuggestion(
        originalFileName: String,
        documentPageCount: Int
    ) -> SongDraftSuggestion {
        let title = URL(filePath: originalFileName)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SongDraftSuggestion(
            title: title.isEmpty ? "제목 없는 찬양" : title,
            startPageNumber: 1,
            endPageNumber: documentPageCount,
            confidence: 0
        )
    }
}
