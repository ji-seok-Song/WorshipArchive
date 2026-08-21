import CoreGraphics
import PDFKit
import UIKit
import XCTest
@testable import WorshipArchive

final class LocalPDFAnalyzerTests: XCTestCase {
    func testRasterizedScoreIsRenderedUprightAndUsesProminentKoreanTitle() async throws {
        let pdfURL = try makeRasterizedScorePDF()
        defer { PDFTestFixture.remove(pdfURL) }

        let analyzer = LocalPDFAnalyzer()
        let result = try await analyzer.analyze(
            pdfAt: pdfURL,
            originalFileName: "합본 악보.pdf",
            expectedPageCount: 1,
            progress: { _ in }
        )

        XCTAssertEqual(result.pages.first?.recognitionMethod, .vision)
        XCTAssertEqual(result.suggestions.first?.title, "주 안에서 기뻐해")
        XCTAssertEqual(result.suggestions.first?.startPageNumber, 1)
        XCTAssertEqual(result.suggestions.first?.endPageNumber, 1)
    }

    func testEmbeddedTextPageUsesOnlyFocusedTitleOCR() async throws {
        let pdfURL = try PDFTestFixture.make(pages: [
            "은혜로다 주의 은혜 날 살리신 주님의 큰 사랑\n"
                + "기쁨으로 주를 노래하며 영원히 찬양합니다"
        ])
        defer { PDFTestFixture.remove(pdfURL) }

        let recognizer = PageTextRecognizerSpy()
        let analyzer = LocalPDFAnalyzer(textRecognizer: recognizer)

        let result = try await analyzer.analyze(
            pdfAt: pdfURL,
            originalFileName: "은혜로다.pdf",
            expectedPageCount: 1,
            progress: { _ in }
        )

        let recognitionCallCount = await recognizer.callCount()
        XCTAssertEqual(recognitionCallCount, 1)
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertEqual(result.pages.first?.recognitionMethod, .embeddedText)
        XCTAssertEqual(result.pages.first?.status, .textExtracted)
    }

    func testImageOnlyPageInvokesOCRAndUsesVisionResult() async throws {
        let pdfURL = try PDFTestFixture.make(pages: [nil])
        defer { PDFTestFixture.remove(pdfURL) }

        let recognizedText = RecognizedPageText(
            text: "새 노래로 주를 찬양",
            confidence: 0.91,
            lines: [
                RecognizedTextLine(
                    text: "새 노래로 주를 찬양",
                    confidence: 0.91,
                    boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.6, height: 0.1)
                )
            ]
        )
        let recognizer = PageTextRecognizerSpy(result: recognizedText)
        let analyzer = LocalPDFAnalyzer(textRecognizer: recognizer)

        let result = try await analyzer.analyze(
            pdfAt: pdfURL,
            originalFileName: "스캔 악보.pdf",
            expectedPageCount: 1,
            progress: { _ in }
        )

        let recognitionCallCount = await recognizer.callCount()
        XCTAssertEqual(recognitionCallCount, 2)
        XCTAssertEqual(result.pages.first?.recognitionMethod, .vision)
        XCTAssertEqual(result.pages.first?.status, .recognized)
        XCTAssertEqual(result.pages.first?.text, "새 노래로 주를 찬양")
        XCTAssertEqual(result.suggestions.first?.title, "새 노래로 주를 찬양")
    }

    func testContinuationPageLyricsDoNotStartAnotherSong() async throws {
        let pdfURL = try PDFTestFixture.make(
            pages: [
                "한 곡의 제목\n첫 페이지에서 주님의 사랑을 기쁨으로 오래 노래합니다",
                "둘째 페이지의 첫 가사 줄입니다\n같은 노래의 가사가 계속 이어집니다"
            ],
            emphasizedTitlePageIndexes: [0]
        )
        defer { PDFTestFixture.remove(pdfURL) }

        let recognizer = PageTextRecognizerSpy()
        let analyzer = LocalPDFAnalyzer(textRecognizer: recognizer)

        let result = try await analyzer.analyze(
            pdfAt: pdfURL,
            originalFileName: "이어지는 찬양.pdf",
            expectedPageCount: 2,
            progress: { _ in }
        )

        XCTAssertEqual(result.suggestions.count, 1)
        XCTAssertEqual(result.suggestions.first?.title, "한 곡의 제목")
        XCTAssertEqual(result.suggestions.first?.startPageNumber, 1)
        XCTAssertEqual(result.suggestions.first?.endPageNumber, 2)
    }

    private func makeRasterizedScorePDF() throws -> URL {
        let size = CGSize(width: 830, height: 1_170)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            ("Intro-V-C-Inter-C-Outro" as NSString).draw(
                at: CGPoint(x: 245, y: 14),
                withAttributes: [.font: UIFont.systemFont(ofSize: 22)]
            )
            ("주 안에서 기뻐해" as NSString).draw(
                at: CGPoint(x: 205, y: 58),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 52)]
            )

            UIColor.black.setStroke()
            for lineIndex in 0..<5 {
                let y = 190 + CGFloat(lineIndex) * 12
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 60, y: y))
                path.addLine(to: CGPoint(x: 770, y: y))
                path.lineWidth = 2
                path.stroke()
            }
            ("주님 주신 기쁨으로 기뻐하라" as NSString).draw(
                at: CGPoint(x: 185, y: 280),
                withAttributes: [.font: UIFont.systemFont(ofSize: 32)]
            )
        }

        let document = PDFDocument()
        let page = try XCTUnwrap(PDFPage(image: image))
        document.insert(page, at: 0)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "RasterizedScore-\(UUID().uuidString).pdf")
        guard document.write(to: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }
}

private actor PageTextRecognizerSpy: PageTextRecognizing {
    private var recordedCallCount = 0
    private let result: RecognizedPageText

    init(
        result: RecognizedPageText = RecognizedPageText(
            text: "",
            confidence: 0,
            lines: []
        )
    ) {
        self.result = result
    }

    func recognizeText(in image: CGImage) async throws -> RecognizedPageText {
        recordedCallCount += 1
        return result
    }

    func callCount() -> Int {
        recordedCallCount
    }
}
