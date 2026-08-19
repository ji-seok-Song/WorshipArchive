import Foundation

nonisolated protocol PDFAnalyzing: Sendable {
    func analyze(
        pdfAt url: URL,
        originalFileName: String,
        expectedPageCount: Int,
        progress: @escaping @Sendable (PDFAnalysisProgress) async -> Void
    ) async throws -> PDFAnalysisResult
}

nonisolated struct PDFAnalysisProgress: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case extractingEmbeddedText
        case recognizingText
        case suggestingSongs
    }

    let stage: Stage
    let completedPageCount: Int
    let totalPageCount: Int
}

nonisolated enum PDFAnalysisError: LocalizedError, Equatable {
    case documentCannotBeOpened
    case pageCountChanged
    case pageCannotBeRead(Int)
    case pageCannotBeRendered(Int)

    var errorDescription: String? {
        switch self {
        case .documentCannotBeOpened:
            "PDF를 분석하기 위해 다시 열 수 없습니다."
        case .pageCountChanged:
            "PDF 페이지 수가 가져온 뒤 변경되었습니다. 다시 선택해 주세요."
        case .pageCannotBeRead(let pageNumber):
            "PDF의 \(pageNumber)페이지를 읽을 수 없습니다."
        case .pageCannotBeRendered(let pageNumber):
            "PDF의 \(pageNumber)페이지를 글자 인식용 이미지로 만들 수 없습니다."
        }
    }
}
