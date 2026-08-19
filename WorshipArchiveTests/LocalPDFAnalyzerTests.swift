import CoreGraphics
import XCTest
@testable import WorshipArchive

final class LocalPDFAnalyzerTests: XCTestCase {
    func testEmbeddedTextPageDoesNotInvokeOCR() async throws {
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
        XCTAssertEqual(recognitionCallCount, 0)
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
        XCTAssertEqual(recognitionCallCount, 1)
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
