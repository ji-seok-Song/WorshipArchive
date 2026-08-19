import Foundation

nonisolated struct PDFAnalysisResult: Equatable, Sendable {
    let pages: [AnalyzedPage]
    let suggestions: [SongDraftSuggestion]

    var failedPageCount: Int {
        pages.filter { $0.errorMessage != nil || $0.status == .failed }.count
    }
}

nonisolated struct AnalyzedPage: Equatable, Sendable {
    let pageIndex: Int
    let text: String
    let recognitionMethod: TextRecognitionMethod
    let status: PageAnalysisStatus
    let confidence: Double
    let errorMessage: String?
    let titleCandidate: TitleCandidate?
}

nonisolated struct TitleCandidate: Equatable, Sendable {
    let text: String
    let confidence: Double
}

nonisolated struct SongDraftSuggestion: Equatable, Sendable {
    let title: String
    let startPageNumber: Int
    let endPageNumber: Int
    let confidence: Double
}
