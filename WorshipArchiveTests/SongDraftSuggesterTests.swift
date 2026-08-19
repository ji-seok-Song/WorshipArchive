import XCTest
@testable import WorshipArchive

final class SongDraftSuggesterTests: XCTestCase {
    private let suggester = SongDraftSuggester(minimumConfidence: 0.65)

    func testRepeatedTitleStartsOnlyOneSong() {
        let suggestions = suggester.suggest(
            pages: [
                page(index: 0, title: "주 사랑", confidence: 0.98),
                page(index: 1, title: "  주 사랑  ", confidence: 0.93)
            ],
            originalFileName: "예배 악보.pdf",
            documentPageCount: 2
        )

        XCTAssertEqual(
            suggestions,
            [
                SongDraftSuggestion(
                    title: "주 사랑",
                    startPageNumber: 1,
                    endPageNumber: 2,
                    confidence: 0.98
                )
            ]
        )
    }

    func testTwoDistinctTitlesProduceTwoNonOverlappingRanges() {
        let suggestions = suggester.suggest(
            pages: [
                page(index: 0, title: "첫 번째 찬양", confidence: 0.92),
                page(index: 2, title: "두 번째 찬양", confidence: 0.87)
            ],
            originalFileName: "주일 예배.pdf",
            documentPageCount: 4
        )

        XCTAssertEqual(
            suggestions,
            [
                SongDraftSuggestion(
                    title: "첫 번째 찬양",
                    startPageNumber: 1,
                    endPageNumber: 2,
                    confidence: 0.92
                ),
                SongDraftSuggestion(
                    title: "두 번째 찬양",
                    startPageNumber: 3,
                    endPageNumber: 4,
                    confidence: 0.87
                )
            ]
        )
    }

    func testNoConfidentTitleFallsBackToOriginalFileNameAndFullRange() {
        let suggestions = suggester.suggest(
            pages: [
                page(index: 0, title: "불확실한 제목", confidence: 0.4),
                page(index: 1, title: nil, confidence: 0)
            ],
            originalFileName: "8월 3주 찬양.pdf",
            documentPageCount: 3
        )

        XCTAssertEqual(
            suggestions,
            [
                SongDraftSuggestion(
                    title: "8월 3주 찬양",
                    startPageNumber: 1,
                    endPageNumber: 3,
                    confidence: 0
                )
            ]
        )
    }

    private func page(
        index: Int,
        title: String?,
        confidence: Double
    ) -> AnalyzedPage {
        AnalyzedPage(
            pageIndex: index,
            text: title ?? "",
            recognitionMethod: .embeddedText,
            status: .textExtracted,
            confidence: confidence,
            errorMessage: nil,
            titleCandidate: title.map {
                TitleCandidate(text: $0, confidence: confidence)
            }
        )
    }
}
