import CoreGraphics
import Foundation

nonisolated protocol PageTextRecognizing: Sendable {
    func recognizeText(in image: CGImage) async throws -> RecognizedPageText
}

nonisolated struct RecognizedPageText: Equatable, Sendable {
    let text: String
    let confidence: Double
    let lines: [RecognizedTextLine]
}

nonisolated struct RecognizedTextLine: Equatable, Sendable {
    let text: String
    let confidence: Double
    let boundingBox: CGRect
}
