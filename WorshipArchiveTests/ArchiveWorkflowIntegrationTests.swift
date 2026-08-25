import CoreGraphics
import Foundation
import PDFKit
import SwiftData
import XCTest
@testable import WorshipArchive

final class ArchiveWorkflowIntegrationTests: XCTestCase {
    @MainActor
    func testImportAnalyzeReviewPersistSearchAndOpenStoredSongRange() async throws {
        let sourceURL = try PDFTestFixture.make(
            pages: [
                "첫 찬양\n끝없는 은혜를 영원히 노래하며 기쁨으로 예배합니다",
                "계속되는 가사\n모든 세대가 함께 주의 사랑을 노래합니다",
                "둘째 찬양\n새 노래로 온 마음 다하여 주님 이름을 높입니다"
            ],
            emphasizedTitlePageIndexes: [0, 2]
        )
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "WorshipArchiveWorkflowTest-\(UUID().uuidString)")
        defer {
            PDFTestFixture.remove(sourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let fileStore = LocalPDFFileStore(rootDirectory: rootDirectory)
        let analyzer = LocalPDFAnalyzer(
            textRecognizer: WorkflowUnexpectedRecognizer()
        )
        let reservation = PDFImportReservation()
        let container = try AppModelContainer.make(inMemory: true)
        let coordinator = PDFImportCoordinator(
            fileStore: fileStore,
            pdfAnalyzer: analyzer,
            importReservation: reservation
        )

        // Import and analyze the real staged copy, then exercise the user review edits.
        await coordinator.stagePDF(from: sourceURL, in: container)

        XCTAssertEqual(coordinator.phase, .reviewing)
        XCTAssertEqual(coordinator.analysisResult?.pages.count, 3)
        XCTAssertEqual(coordinator.drafts.count, 2)

        let firstDraftIndex = try XCTUnwrap(
            coordinator.drafts.firstIndex { $0.startPageNumber == 1 }
        )
        XCTAssertEqual(coordinator.drafts[firstDraftIndex].endPageNumber, 2)
        coordinator.drafts[firstDraftIndex].title = "영원한 사랑"
        coordinator.drafts[firstDraftIndex].musicalKey = .gMajor

        XCTAssertTrue(coordinator.canSave)
        let didSave = await coordinator.save(in: container)
        XCTAssertTrue(didSave)
        XCTAssertEqual(coordinator.phase, .completed)

        // Fetch from SwiftData as the library/search screens do.
        let context = ModelContext(container)
        let documents = try context.fetch(FetchDescriptor<ArchiveDocument>())
        let pages = try context.fetch(FetchDescriptor<PageAnalysis>())
        let songs = try context.fetch(FetchDescriptor<Song>())

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?.analysisStatus, .completed)
        XCTAssertEqual(pages.map(\.pageIndex).sorted(), [0, 1, 2])
        XCTAssertEqual(songs.count, 2)

        let matches = SongSearchMatcher.filter(
            songs,
            using: SongSearchFilter(
                query: "영원한 사랑",
                musicalKey: .gMajor
            )
        )
        let matchedSong = try XCTUnwrap(matches.first)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matchedSong.title, "영원한 사랑")

        let sheet = try XCTUnwrap(matchedSong.sheets?.first)
        let document = try XCTUnwrap(sheet.document)
        XCTAssertEqual(sheet.startPageIndex, 0)
        XCTAssertEqual(sheet.endPageIndex, 1)

        // Open through the same checksum-validated local store and PDF loader as the UI.
        let viewerLoader = PDFViewerLoader(fileAccess: fileStore)
        let loadedResult = await viewerLoader.load(
            document: document,
            sheet: sheet
        )
        let loadedDocument = try XCTUnwrap(
            loadedResult
        )
        XCTAssertEqual(loadedDocument.document.pageCount, 2)
        XCTAssertEqual(loadedDocument.pageSession.startPageIndex, 0)
        XCTAssertEqual(loadedDocument.pageSession.endPageIndex, 1)
        XCTAssertEqual(loadedDocument.pageSession.initialPageIndex, 0)

        let openedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try PDFViewerSessionPersistence.recordOpened(
            sheet: sheet,
            pageIndex: loadedDocument.pageSession.initialPageIndex,
            at: openedAt,
            in: context
        )

        let verificationContext = ModelContext(container)
        let matchedSongID = matchedSong.id
        let savedSong = try XCTUnwrap(
            verificationContext.fetch(
                FetchDescriptor<Song>(
                    predicate: #Predicate { song in
                        song.id == matchedSongID
                    }
                )
            ).first
        )
        XCTAssertEqual(savedSong.lastOpenedAt, openedAt)

        // A repeated import must not create another document or leave staged data behind.
        let duplicateCoordinator = PDFImportCoordinator(
            fileStore: fileStore,
            pdfAnalyzer: analyzer,
            importReservation: reservation
        )
        await duplicateCoordinator.stagePDF(from: sourceURL, in: container)

        XCTAssertEqual(duplicateCoordinator.phase, .selecting)
        XCTAssertNotNil(duplicateCoordinator.errorMessage)
        XCTAssertEqual(
            try verificationContext.fetch(FetchDescriptor<ArchiveDocument>()).count,
            1
        )

        let stagingDirectory = rootDirectory.appending(
            path: "Staging",
            directoryHint: .isDirectory
        )
        let stagedFileNames = try FileManager.default.contentsOfDirectory(
            atPath: stagingDirectory.path
        )
        XCTAssertTrue(stagedFileNames.isEmpty)
    }
}

private actor WorkflowUnexpectedRecognizer: PageTextRecognizing {
    func recognizeText(in image: CGImage) async throws -> RecognizedPageText {
        throw WorkflowUnexpectedRecognitionError()
    }
}

private struct WorkflowUnexpectedRecognitionError: Error {}
