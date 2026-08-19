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

        var starts: [(pageIndex: Int, title: String, confidence: Double)] = []
        var previousNormalizedTitle: String?

        for page in pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            guard (0..<documentPageCount).contains(page.pageIndex) else { continue }
            guard let candidate = page.titleCandidate else { continue }
            guard candidate.confidence >= minimumConfidence else { continue }

            let title = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = SearchTextNormalizer.normalize(title)
            guard !normalizedTitle.isEmpty else { continue }
            guard normalizedTitle != previousNormalizedTitle else { continue }

            starts.append((
                pageIndex: page.pageIndex,
                title: title,
                confidence: min(max(candidate.confidence, 0), 1)
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
                confidence: start.confidence
            )
        }
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
