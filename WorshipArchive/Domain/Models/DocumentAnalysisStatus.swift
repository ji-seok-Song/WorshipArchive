import Foundation

enum DocumentAnalysisStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case extractingText
    case recognizingText
    case awaitingReview
    case completed
    case failed
}

enum PageAnalysisStatus: String, Codable, Sendable {
    case pending
    case textExtracted
    case recognitionRequired
    case recognized
    case failed
}

enum TextRecognitionMethod: String, Codable, Sendable {
    case none
    case embeddedText
    case vision
}
