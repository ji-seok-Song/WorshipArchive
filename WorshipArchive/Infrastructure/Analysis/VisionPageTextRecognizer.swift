import CoreGraphics
import Foundation
@preconcurrency import Vision

actor VisionPageTextRecognizer: PageTextRecognizing {
    func recognizeText(in image: CGImage) async throws -> RecognizedPageText {
        try Task.checkCancellation()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try await withTaskCancellationHandler {
            do {
                try handler.perform([request])
            } catch {
                try Task.checkCancellation()
                throw error
            }
            try Task.checkCancellation()
        } onCancel: {
            request.cancel()
        }

        let lines = (request.results ?? [])
            .compactMap { observation -> RecognizedTextLine? in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }
                let text = candidate.string.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !text.isEmpty else { return nil }

                return RecognizedTextLine(
                    text: text,
                    confidence: Double(candidate.confidence),
                    boundingBox: observation.boundingBox
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.boundingBox.maxY - rhs.boundingBox.maxY) > 0.015 {
                    return lhs.boundingBox.maxY > rhs.boundingBox.maxY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }

        let weightedCharacterCount = lines.reduce(0) { partialResult, line in
            partialResult + max(line.text.count, 1)
        }
        let confidence: Double
        if weightedCharacterCount == 0 {
            confidence = 0
        } else {
            confidence = lines.reduce(0) { partialResult, line in
                partialResult + line.confidence * Double(max(line.text.count, 1))
            } / Double(weightedCharacterCount)
        }

        return RecognizedPageText(
            text: lines.map(\.text).joined(separator: "\n"),
            confidence: confidence,
            lines: lines
        )
    }
}
