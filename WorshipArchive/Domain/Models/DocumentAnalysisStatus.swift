import Foundation

enum DocumentAnalysisStatus: String, Codable, CaseIterable {
    case pending
    case extractingText
    case recognizingText
    case awaitingReview
    case completed
    case failed
}

enum PageAnalysisStatus: String, Codable {
    case pending
    case textExtracted
    case recognitionRequired
    case recognized
    case failed
}

enum TextRecognitionMethod: String, Codable {
    case none
    case embeddedText
    case vision
}
