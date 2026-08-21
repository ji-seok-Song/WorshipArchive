import Foundation

nonisolated struct SongDraftSuggester: Sendable {
    let minimumConfidence: Double
    private let keyDetector = ScoreKeyDetector()

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
        var starts: [(
            pageIndex: Int,
            title: String,
            confidence: Double,
            keyCandidate: ScoreKeyCandidate?
        )] = []
        var previousNormalizedTitle: String?

        for page in pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            guard (0..<documentPageCount).contains(page.pageIndex) else { continue }
            guard let candidate = page.titleCandidate else { continue }
            guard candidate.confidence >= minimumConfidence else { continue }

            let title = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = SearchTextNormalizer.normalize(title)
            guard !normalizedTitle.isEmpty else { continue }
            guard !recurringMarks.contains(normalizedTitle) else { continue }
            guard normalizedTitle != previousNormalizedTitle else { continue }
            guard strippingTrailingPageNumber(from: normalizedTitle)
                    != previousNormalizedTitle else {
                continue
            }

            starts.append((
                pageIndex: page.pageIndex,
                title: title,
                confidence: min(max(candidate.confidence, 0), 1),
                keyCandidate: keyDetector.detect(in: page.text)
            ))
            previousNormalizedTitle = normalizedTitle
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
                confidence: start.confidence,
                musicalKey: start.keyCandidate?.musicalKey,
                keyConfidence: start.keyCandidate?.confidence
            )
        }
    }

    private func recurringShortLatinMarks(in pages: [AnalyzedPage]) -> Set<String> {
        let candidates = pages.compactMap { page -> (normalized: String, original: String)? in
            guard let title = page.titleCandidate?.text else { return nil }
            let normalized = SearchTextNormalizer.normalize(title)
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
