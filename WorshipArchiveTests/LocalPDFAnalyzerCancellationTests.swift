import CoreGraphics
import XCTest
@testable import WorshipArchive

final class LocalPDFAnalyzerCancellationTests: XCTestCase {
    func testCancellationIsNotConvertedIntoPageFailureWhenRecognizerThrowsFrameworkError() async throws {
        let pdfURL = try PDFTestFixture.make(pages: [nil])
        defer { PDFTestFixture.remove(pdfURL) }

        let recognizer = CancellationTranslatingRecognizer()
        let analyzer = LocalPDFAnalyzer(textRecognizer: recognizer)
        let analysisTask = Task {
            try await analyzer.analyze(
                pdfAt: pdfURL,
                originalFileName: "취소 테스트.pdf",
                expectedPageCount: 1,
                progress: { _ in }
            )
        }

        await recognizer.waitUntilStarted()
        analysisTask.cancel()

        do {
            _ = try await analysisTask.value
            XCTFail("취소된 분석이 페이지 실패 결과로 완료되면 안 됩니다.")
        } catch is CancellationError {
            // Expected: framework-specific cancellation errors are normalized.
        } catch {
            XCTFail("CancellationError가 필요하지만 \(error)가 발생했습니다.")
        }
    }

    func testCancellationFromFinalProgressCallbackPreventsResultFromReturning() async throws {
        let pdfURL = try PDFTestFixture.make(pages: [
            "마지막 취소 검사 찬양\n분석 완료 직전에도 취소를 정확하게 전파합니다"
        ])
        defer { PDFTestFixture.remove(pdfURL) }

        let analyzer = LocalPDFAnalyzer(textRecognizer: UnexpectedPageTextRecognizer())
        let analysisTask = Task {
            try await analyzer.analyze(
                pdfAt: pdfURL,
                originalFileName: "마지막 취소 검사.pdf",
                expectedPageCount: 1
            ) { progress in
                guard
                    progress.stage == .suggestingSongs,
                    progress.completedPageCount == progress.totalPageCount
                else {
                    return
                }

                withUnsafeCurrentTask { task in
                    task?.cancel()
                }
            }
        }

        do {
            _ = try await analysisTask.value
            XCTFail("마지막 진행률 콜백에서 취소된 분석이 결과를 반환하면 안 됩니다.")
        } catch is CancellationError {
            // Expected: the final cancellation checkpoint rejects the result.
        } catch {
            XCTFail("CancellationError가 필요하지만 \(error)가 발생했습니다.")
        }
    }
}

private actor CancellationTranslatingRecognizer: PageTextRecognizing {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func recognizeText(in image: CGImage) async throws -> RecognizedPageText {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        do {
            try await Task<Never, Never>.sleep(nanoseconds: 60_000_000_000)
        } catch is CancellationError {
            throw SimulatedVisionCancellationError()
        }

        throw SimulatedVisionCancellationError()
    }

    func waitUntilStarted() async {
        guard !didStart else { return }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}

private actor UnexpectedPageTextRecognizer: PageTextRecognizing {
    func recognizeText(in image: CGImage) async throws -> RecognizedPageText {
        throw UnexpectedRecognitionError()
    }
}

private struct SimulatedVisionCancellationError: Error {}
private struct UnexpectedRecognitionError: Error {}
