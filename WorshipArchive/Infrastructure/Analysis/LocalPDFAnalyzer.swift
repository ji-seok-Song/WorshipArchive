import CoreGraphics
import Foundation
import PDFKit
import UIKit

actor LocalPDFAnalyzer: PDFAnalyzing {
    private struct EmbeddedPageSeed {
        let pageIndex: Int
        let text: String
        let titleCandidate: TitleCandidate?
        let needsRecognition: Bool
    }

    private let textRecognizer: any PageTextRecognizing
    private let suggester: SongDraftSuggester

    init(
        textRecognizer: any PageTextRecognizing = VisionPageTextRecognizer(),
        suggester: SongDraftSuggester = SongDraftSuggester()
    ) {
        self.textRecognizer = textRecognizer
        self.suggester = suggester
    }

    func analyze(
        pdfAt url: URL,
        originalFileName: String,
        expectedPageCount: Int,
        progress: @escaping @Sendable (PDFAnalysisProgress) async -> Void
    ) async throws -> PDFAnalysisResult {
        guard let document = PDFDocument(url: url) else {
            throw PDFAnalysisError.documentCannotBeOpened
        }
        guard document.pageCount == expectedPageCount, expectedPageCount > 0 else {
            throw PDFAnalysisError.pageCountChanged
        }

        var seeds: [EmbeddedPageSeed] = []
        var analyzedPages: [Int: AnalyzedPage] = [:]

        for pageIndex in 0..<expectedPageCount {
            try Task.checkCancellation()

            if let page = document.page(at: pageIndex) {
                let embeddedText = normalizedText(page.string ?? "")
                let needsRecognition = needsTextRecognition(embeddedText)
                let embeddedTitleCandidate = titleCandidate(
                    from: page,
                    fallbackText: embeddedText
                )
                let recognizedFocusedTitle = needsRecognition
                    ? nil
                    : try await recognizeFocusedTitle(on: page)
                let focusedTitleCandidate = recognizedFocusedTitle.flatMap { candidate in
                    candidate.confidence >= 0.65 ? candidate : nil
                }
                let seed = EmbeddedPageSeed(
                    pageIndex: pageIndex,
                    text: embeddedText,
                    titleCandidate: focusedTitleCandidate ?? embeddedTitleCandidate,
                    needsRecognition: needsRecognition
                )
                seeds.append(seed)

                if !seed.needsRecognition {
                    analyzedPages[pageIndex] = AnalyzedPage(
                        pageIndex: pageIndex,
                        text: embeddedText,
                        recognitionMethod: .embeddedText,
                        status: .textExtracted,
                        confidence: 1,
                        errorMessage: nil,
                        titleCandidate: seed.titleCandidate
                    )
                }
            } else {
                let error = PDFAnalysisError.pageCannotBeRead(pageIndex + 1)
                analyzedPages[pageIndex] = failedPage(
                    pageIndex: pageIndex,
                    fallbackText: "",
                    fallbackTitle: nil,
                    error: error
                )
            }

            await progress(PDFAnalysisProgress(
                stage: .extractingEmbeddedText,
                completedPageCount: pageIndex + 1,
                totalPageCount: expectedPageCount
            ))
        }

        let recognitionSeeds = seeds.filter(\.needsRecognition)
        for (offset, seed) in recognitionSeeds.enumerated() {
            try Task.checkCancellation()

            guard let page = document.page(at: seed.pageIndex) else {
                let error = PDFAnalysisError.pageCannotBeRead(seed.pageIndex + 1)
                analyzedPages[seed.pageIndex] = failedPage(
                    pageIndex: seed.pageIndex,
                    fallbackText: seed.text,
                    fallbackTitle: seed.titleCandidate,
                    error: error
                )
                continue
            }

            do {
                guard let image = render(page: page) else {
                    throw PDFAnalysisError.pageCannotBeRendered(seed.pageIndex + 1)
                }

                let recognizedText = try await textRecognizer.recognizeText(in: image)
                try Task.checkCancellation()

                let text = normalizedText(recognizedText.text)
                if text.isEmpty {
                    let error = TextRecognitionError.noTextFound
                    analyzedPages[seed.pageIndex] = failedPage(
                        pageIndex: seed.pageIndex,
                        fallbackText: seed.text,
                        fallbackTitle: seed.titleCandidate,
                        error: error
                    )
                } else {
                    let fullPageTitleCandidate = titleCandidate(
                        from: recognizedText.lines,
                        fallbackText: text
                    )
                    let recognizedFocusedTitle = try await recognizeFocusedTitle(on: page)
                    let focusedTitleCandidate = recognizedFocusedTitle.flatMap { candidate in
                        candidate.confidence >= 0.65 ? candidate : nil
                    }
                    analyzedPages[seed.pageIndex] = AnalyzedPage(
                        pageIndex: seed.pageIndex,
                        text: text,
                        recognitionMethod: .vision,
                        status: .recognized,
                        confidence: min(max(recognizedText.confidence, 0), 1),
                        errorMessage: nil,
                        titleCandidate: focusedTitleCandidate ?? fullPageTitleCandidate
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                analyzedPages[seed.pageIndex] = failedPage(
                    pageIndex: seed.pageIndex,
                    fallbackText: seed.text,
                    fallbackTitle: seed.titleCandidate,
                    error: error
                )
            }

            await progress(PDFAnalysisProgress(
                stage: .recognizingText,
                completedPageCount: offset + 1,
                totalPageCount: recognitionSeeds.count
            ))
        }

        try Task.checkCancellation()
        let pages = (0..<expectedPageCount).map { pageIndex in
            analyzedPages[pageIndex] ?? failedPage(
                pageIndex: pageIndex,
                fallbackText: "",
                fallbackTitle: nil,
                error: PDFAnalysisError.pageCannotBeRead(pageIndex + 1)
            )
        }

        await progress(PDFAnalysisProgress(
            stage: .suggestingSongs,
            completedPageCount: 0,
            totalPageCount: 1
        ))
        try Task.checkCancellation()
        let suggestions = suggester.suggest(
            pages: pages,
            originalFileName: originalFileName,
            documentPageCount: expectedPageCount
        )
        await progress(PDFAnalysisProgress(
            stage: .suggestingSongs,
            completedPageCount: 1,
            totalPageCount: 1
        ))
        try Task.checkCancellation()

        return PDFAnalysisResult(pages: pages, suggestions: suggestions)
    }

    private func needsTextRecognition(_ text: String) -> Bool {
        let meaningfulCharacterCount = text.unicodeScalars.reduce(0) { count, scalar in
            CharacterSet.alphanumerics.contains(scalar) ? count + 1 : count
        }
        let meaningfulLineCount = text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .filter { line in
                line.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count >= 2
            }
            .count
        let replacementCharacterCount = text.filter { $0 == "�" }.count
        let replacementRatio = text.isEmpty
            ? 0
            : Double(replacementCharacterCount) / Double(text.count)

        return meaningfulCharacterCount < 24
            || meaningfulLineCount < 2
            || replacementRatio > 0.1
    }

    private func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func titleCandidate(
        from lines: [RecognizedTextLine],
        fallbackText: String,
        isFocusedTitleRegion: Bool = false
    ) -> TitleCandidate? {
        let plausibleLines = lines.filter { line in
            let minimumY = isFocusedTitleRegion ? 0.3 : 0.65
            return line.boundingBox.maxY >= minimumY
                && isPlausibleTitle(line.text)
                && !isScoreAnnotation(line.text)
        }
        let heights = plausibleLines.map { $0.boundingBox.height }.sorted()
        let medianHeight = heights.isEmpty ? 0 : heights[heights.count / 2]
        let maximumHeight = heights.last ?? 0

        if isFocusedTitleRegion,
           let combinedCandidate = combinedFocusedTitleCandidate(
               from: plausibleLines,
               maximumHeight: maximumHeight
           ) {
            return combinedCandidate
        }

        let rankedLines = plausibleLines.sorted { lhs, rhs in
            titleLineScore(lhs, maximumHeight: maximumHeight)
                > titleLineScore(rhs, maximumHeight: maximumHeight)
        }
        if let line = rankedLines.first(where: { line in
            let isProminent = plausibleLines.count == 1
                || line.boundingBox.height >= medianHeight * 1.15
                || line.boundingBox.height >= maximumHeight * 0.8
            let isLargeEnoughForFocusedPass = !isFocusedTitleRegion
                || line.boundingBox.height >= 0.11
            return isProminent && isLargeEnoughForFocusedPass
        }) {
            let confidence = isFocusedTitleRegion
                ? max(line.confidence, 0.78)
                : line.confidence
            return TitleCandidate(
                text: cleanedTitle(line.text),
                confidence: min(max(confidence, 0), 1)
            )
        }
        return titleCandidate(from: fallbackText, confidence: 0.62)
    }

    private func combinedFocusedTitleCandidate(
        from lines: [RecognizedTextLine],
        maximumHeight: CGFloat
    ) -> TitleCandidate? {
        guard maximumHeight > 0 else { return nil }
        let prominentLines = lines
            .filter { line in
                let centerDistance = abs(line.boundingBox.midX - 0.5)
                return line.boundingBox.height >= maximumHeight * 0.68
                    && centerDistance <= 0.24
            }
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        guard prominentLines.count >= 2 else { return nil }

        for index in 0..<(prominentLines.count - 1) {
            let upper = prominentLines[index]
            let lower = prominentLines[index + 1]
            let verticalGap = upper.boundingBox.minY - lower.boundingBox.maxY
            guard (-0.03...0.24).contains(verticalGap) else { continue }
            guard containsHangul(upper.text) == containsHangul(lower.text) else {
                continue
            }

            let combined = "\(cleanedTitle(upper.text)) \(cleanedTitle(lower.text))"
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleTitle(combined), combined.count <= 80 else { continue }

            return TitleCandidate(
                text: combined,
                confidence: min(max(min(upper.confidence, lower.confidence), 0.78), 1)
            )
        }
        return nil
    }

    private func containsHangul(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)
                || (0x3131...0x318E).contains(scalar.value)
        }
    }

    private func recognizeFocusedTitle(on page: PDFPage) async throws -> TitleCandidate? {
        guard let image = renderTitleRegion(page: page) else { return nil }

        do {
            let recognizedTitle = try await textRecognizer.recognizeText(in: image)
            try Task.checkCancellation()
            return titleCandidate(
                from: recognizedTitle.lines,
                fallbackText: normalizedText(recognizedTitle.text),
                isFocusedTitleRegion: true
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func titleLineScore(
        _ line: RecognizedTextLine,
        maximumHeight: CGFloat
    ) -> Double {
        let heightScore = maximumHeight > 0
            ? Double(line.boundingBox.height / maximumHeight)
            : 0
        let centerDistance = min(abs(Double(line.boundingBox.midX) - 0.5) * 2, 1)
        let centerScore = 1 - centerDistance
        return heightScore * 0.65 + line.confidence * 0.2 + centerScore * 0.15
    }

    private func titleCandidate(
        from page: PDFPage,
        fallbackText: String
    ) -> TitleCandidate? {
        guard let attributedText = page.attributedString, attributedText.length > 0 else {
            return titleCandidate(from: fallbackText, confidence: 0.62)
        }

        var fontUsage: [CGFloat: Int] = [:]
        attributedText.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, range, _ in
            guard let font = value as? UIFont else { return }
            guard let key = PDFTextFontSizing.bucketedPointSize(font.pointSize) else {
                return
            }
            fontUsage[key, default: 0] += range.length
        }
        guard let bodyFontKey = fontUsage.max(by: { $0.value < $1.value })?.key else {
            return titleCandidate(from: fallbackText, confidence: 0.62)
        }
        let bodyFontSize = bodyFontKey

        let string = attributedText.string as NSString
        var location = 0
        var inspectedLineCount = 0
        while location < string.length, inspectedLineCount < 8 {
            let lineRange = string.lineRange(
                for: NSRange(location: location, length: 0)
            )
            guard lineRange.length > 0 else { break }
            let line = string.substring(with: lineRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var largestFontSize: CGFloat = 0
            attributedText.enumerateAttribute(
                .font,
                in: lineRange
            ) { value, _, _ in
                guard let font = value as? UIFont else { return }
                guard let pointSize = PDFTextFontSizing.bucketedPointSize(font.pointSize) else {
                    return
                }
                largestFontSize = max(largestFontSize, pointSize)
            }

            if isPlausibleTitle(line),
               largestFontSize >= bodyFontSize + 1.5,
               largestFontSize >= bodyFontSize * 1.15 {
                return TitleCandidate(text: cleanedTitle(line), confidence: 0.88)
            }

            location = NSMaxRange(lineRange)
            inspectedLineCount += 1
        }

        return titleCandidate(from: fallbackText, confidence: 0.62)
    }

    private func titleCandidate(
        from text: String,
        confidence: Double
    ) -> TitleCandidate? {
        guard let line = text
            .split(whereSeparator: \Character.isNewline)
            .prefix(8)
            .map(String.init)
            .first(where: isPlausibleTitle)
        else {
            return nil
        }

        return TitleCandidate(
            text: cleanedTitle(line),
            confidence: confidence
        )
    }

    private func cleanedTitle(_ value: String) -> String {
        var title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstHangulIndex = title.firstIndex(where: { character in
            character.unicodeScalars.contains(where: { scalar in
                (0xAC00...0xD7A3).contains(scalar.value)
                    || (0x3131...0x318E).contains(scalar.value)
            })
        }), firstHangulIndex != title.startIndex {
            let prefix = title[..<firstHangulIndex]
            let latinOrSymbolCount = prefix.unicodeScalars.filter { scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || CharacterSet.punctuationCharacters.contains(scalar)
            }.count
            if prefix.count >= 4,
               Double(latinOrSymbolCount) / Double(prefix.count) >= 0.65 {
                title = String(title[firstHangulIndex...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard title.hasSuffix(")"), let opening = title.lastIndex(of: "(") else {
            return title
        }

        let annotation = title[title.index(after: opening)..<title.index(before: title.endIndex)]
            .lowercased()
        let removableMarkers = [
            "화음", "편곡", "악보", "version", "ver.", " ver", "key", "mr", "live"
        ]
        guard removableMarkers.contains(where: annotation.contains) else {
            return title
        }

        let baseTitle = title[..<opening]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return baseTitle.isEmpty ? title : baseTitle
    }

    private func isPlausibleTitle(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(text.count) else { return false }
        guard text.unicodeScalars.contains(where: CharacterSet.letters.contains) else {
            return false
        }

        let compact = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "¾", with: "#")
            .lowercased()
        let chordCharacters = CharacterSet(charactersIn: "abcdefg#b/0123456789msujdimt()-*?♭♯")
        let looksLikeChord = compact.count <= 40
            && compact.unicodeScalars.allSatisfy(chordCharacters.contains)
        guard !looksLikeChord else { return false }

        guard let first = text.first, !first.isNumber else { return false }
        return true
    }

    private func isScoreAnnotation(_ value: String) -> Bool {
        let normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        let creditMarkers = [
            "wordsby", "musicby", "scoredby", "arrangedby",
            "작사", "작곡", "편곡", "채보"
        ]
        if creditMarkers.contains(where: normalized.contains) {
            return true
        }

        let sectionMarkers = [
            "intro", "verse", "chorus", "bridge", "inter", "outro",
            "prechorus", "keychange", "keyup", "d.s.", "d.c.", "fine",
            "마디", "파트", "번째", "부터", "패턴", "section", "solo", "rit",
            "mute", "brake", "drum"
        ]
        if sectionMarkers.contains(where: normalized.contains) {
            return true
        }

        let separatorCount = normalized.filter { "-x>".contains($0) }.count
        return normalized.count >= 8 && separatorCount >= 2
    }

    private func failedPage(
        pageIndex: Int,
        fallbackText: String,
        fallbackTitle: TitleCandidate?,
        error: Error
    ) -> AnalyzedPage {
        let hasFallbackText = !fallbackText.isEmpty
        return AnalyzedPage(
            pageIndex: pageIndex,
            text: fallbackText,
            recognitionMethod: hasFallbackText ? .embeddedText : .vision,
            status: hasFallbackText ? .recognitionRequired : .failed,
            confidence: hasFallbackText ? 0.35 : 0,
            errorMessage: error.localizedDescription,
            titleCandidate: fallbackTitle
        )
    }

    private func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let longestSide = max(bounds.width, bounds.height)
        guard
            bounds.width.isFinite,
            bounds.height.isFinite,
            bounds.width > 0,
            bounds.height > 0,
            longestSide > 0
        else {
            return nil
        }

        let scale = min(2, 3000 / longestSide)
        let width = max(Int(ceil(bounds.width * scale)), 1)
        let height = max(Int(ceil(bounds.height * scale)), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(
            x: CGFloat(width) / bounds.width,
            y: CGFloat(height) / bounds.height
        )
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }

    private func renderTitleRegion(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard
            bounds.width.isFinite,
            bounds.height.isFinite,
            bounds.width > 0,
            bounds.height > 0
        else {
            return nil
        }

        // Score sheets place the title in the shallow top band. Keeping staff
        // lines and chord symbols out of this pass materially improves Korean OCR.
        let titleRegionHeight = bounds.height * 0.11
        let titleRegion = CGRect(
            x: bounds.minX,
            y: bounds.maxY - titleRegionHeight,
            width: bounds.width,
            height: titleRegionHeight
        )
        let longestSide = max(titleRegion.width, titleRegion.height)
        let scale = min(6, 3000 / longestSide)
        let width = max(Int(ceil(titleRegion.width * scale)), 1)
        let height = max(Int(ceil(titleRegion.height * scale)), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(
            x: CGFloat(width) / titleRegion.width,
            y: CGFloat(height) / titleRegion.height
        )
        context.translateBy(x: -titleRegion.minX, y: -titleRegion.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }
}

nonisolated enum PDFTextFontSizing {
    static let maximumPointSize: CGFloat = 10_000

    static func bucketedPointSize(_ pointSize: CGFloat) -> CGFloat? {
        guard pointSize.isFinite, pointSize > 0 else { return nil }

        let boundedPointSize = min(pointSize, maximumPointSize)
        return (boundedPointSize * 2).rounded() / 2
    }
}

private enum TextRecognitionError: LocalizedError {
    case noTextFound

    var errorDescription: String? {
        "페이지에서 인식할 수 있는 글자를 찾지 못했습니다."
    }
}
