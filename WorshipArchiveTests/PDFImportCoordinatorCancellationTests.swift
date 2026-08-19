import Foundation
import SwiftData
import XCTest
@testable import WorshipArchive

final class PDFImportCoordinatorCancellationTests: XCTestCase {
    @MainActor
    func testCancelReleasesPendingReservationBeforeAnalyzerReturns() async throws {
        let sourceURL = try PDFTestFixture.make(pages: [
            "취소 테스트 찬양\n분석이 끝나지 않아도 다시 가져올 수 있어야 합니다"
        ])
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "WorshipArchiveCancellationTest-\(UUID().uuidString)")
        defer {
            PDFTestFixture.remove(sourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let fileStore = LocalPDFFileStore(rootDirectory: rootDirectory)
        let analyzer = SuspendingPDFAnalyzer()
        let reservation = PDFImportReservation()
        let container = try AppModelContainer.make(inMemory: true)
        let firstCoordinator = PDFImportCoordinator(
            fileStore: fileStore,
            pdfAnalyzer: analyzer,
            importReservation: reservation
        )
        let secondCoordinator = PDFImportCoordinator(
            fileStore: fileStore,
            pdfAnalyzer: analyzer,
            importReservation: reservation
        )

        let firstImport = Task {
            await firstCoordinator.stagePDF(from: sourceURL, in: container)
        }
        try await waitForAnalyzer(analyzer, toStart: 1)

        await firstCoordinator.cancel()
        XCTAssertEqual(firstCoordinator.phase, .selecting)

        let secondImport = Task {
            await secondCoordinator.stagePDF(from: sourceURL, in: container)
        }
        try await waitForAnalyzer(analyzer, toStart: 2)
        XCTAssertEqual(secondCoordinator.phase, .analyzing)
        XCTAssertNil(secondCoordinator.errorMessage)

        await analyzer.resumeAll()
        await firstImport.value
        await secondImport.value

        XCTAssertEqual(secondCoordinator.phase, .reviewing)
        XCTAssertTrue(secondCoordinator.canSave)
        await secondCoordinator.cancel()
    }

    @MainActor
    private func waitForAnalyzer(
        _ analyzer: SuspendingPDFAnalyzer,
        toStart expectedCount: Int
    ) async throws {
        for _ in 0..<10_000 {
            if await analyzer.startedCount >= expectedCount { return }
            await Task.yield()
        }
        throw AnalyzerWaitError.timedOut
    }
}

private actor SuspendingPDFAnalyzer: PDFAnalyzing {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var startedCount: Int {
        continuations.count
    }

    func analyze(
        pdfAt url: URL,
        originalFileName: String,
        expectedPageCount: Int,
        progress: @escaping @Sendable (PDFAnalysisProgress) async -> Void
    ) async throws -> PDFAnalysisResult {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }

        let pages = (0..<expectedPageCount).map { pageIndex in
            AnalyzedPage(
                pageIndex: pageIndex,
                text: "취소 테스트 찬양",
                recognitionMethod: .embeddedText,
                status: .textExtracted,
                confidence: 0.9,
                errorMessage: nil,
                titleCandidate: pageIndex == 0
                    ? TitleCandidate(text: "취소 테스트 찬양", confidence: 0.9)
                    : nil
            )
        }
        return PDFAnalysisResult(
            pages: pages,
            suggestions: [
                SongDraftSuggestion(
                    title: "취소 테스트 찬양",
                    startPageNumber: 1,
                    endPageNumber: expectedPageCount,
                    confidence: 0.9
                )
            ]
        )
    }

    func resumeAll() {
        let pendingContinuations = continuations
        continuations.removeAll()
        pendingContinuations.forEach { $0.resume() }
    }
}

private enum AnalyzerWaitError: Error {
    case timedOut
}
