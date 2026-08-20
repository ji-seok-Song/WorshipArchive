import Foundation
import PDFKit
import SwiftData
import XCTest
@testable import WorshipArchive

final class PDFViewerTests: XCTestCase {
    @MainActor
    func testPDFKitCoordinatorSuppressesInitialNavigationAndReappliesSession() async throws {
        let pdfURL = try PDFTestFixture.make(pages: ["첫 장", "둘째 장", "셋째 장"])
        defer { PDFTestFixture.remove(pdfURL) }
        let document = try XCTUnwrap(PDFDocument(url: pdfURL))
        let firstSession = try PDFViewerPageSession(
            startPageIndex: 0,
            endPageIndex: 2,
            lastViewedPageIndex: 2,
            documentPageCount: 3
        )
        var reportedPages: [Int] = []
        let firstBridge = PDFKitScoreView(
            document: document,
            pageSession: firstSession,
            onPageChanged: { reportedPages.append($0) }
        )
        let coordinator = firstBridge.makeCoordinator()
        let pdfView = PDFView()

        coordinator.update(parent: firstBridge, pdfView: pdfView)
        await waitForNextMainTurn()

        XCTAssertEqual(currentPageIndex(in: pdfView), 2)
        XCTAssertTrue(reportedPages.isEmpty)

        let changedSession = try PDFViewerPageSession(
            startPageIndex: 0,
            endPageIndex: 2,
            lastViewedPageIndex: 1,
            documentPageCount: 3
        )
        let changedBridge = PDFKitScoreView(
            document: document,
            pageSession: changedSession,
            onPageChanged: { reportedPages.append($0) }
        )

        coordinator.update(parent: changedBridge, pdfView: pdfView)
        await waitForNextMainTurn()

        XCTAssertEqual(currentPageIndex(in: pdfView), 1)
        XCTAssertTrue(reportedPages.isEmpty)

        pdfView.go(to: try XCTUnwrap(document.page(at: 2)))
        await waitForNextMainTurn()
        XCTAssertEqual(reportedPages, [2])
    }

    @MainActor
    func testPDFKitApplicationIdentityIncludesEveryPageSessionValue() throws {
        let document = PDFDocument()
        let baseline = try PDFViewerPageSession(
            startPageIndex: 1,
            endPageIndex: 4,
            lastViewedPageIndex: 2,
            documentPageCount: 5
        )
        let changedStart = try PDFViewerPageSession(
            startPageIndex: 0,
            endPageIndex: 4,
            lastViewedPageIndex: 2,
            documentPageCount: 5
        )
        let changedEnd = try PDFViewerPageSession(
            startPageIndex: 1,
            endPageIndex: 3,
            lastViewedPageIndex: 2,
            documentPageCount: 5
        )
        let changedInitial = try PDFViewerPageSession(
            startPageIndex: 1,
            endPageIndex: 4,
            lastViewedPageIndex: 3,
            documentPageCount: 5
        )
        var state = PDFKitScoreApplicationState()

        XCTAssertTrue(state.beginApplying(.init(document: document, pageSession: baseline)))
        XCTAssertFalse(state.shouldForwardPageChange)
        XCTAssertTrue(state.finishApplying(.init(document: document, pageSession: baseline)))
        XCTAssertTrue(state.shouldForwardPageChange)
        XCTAssertFalse(state.beginApplying(.init(document: document, pageSession: baseline)))
        XCTAssertTrue(state.beginApplying(.init(document: document, pageSession: changedStart)))
        XCTAssertTrue(state.finishApplying(.init(document: document, pageSession: changedStart)))
        XCTAssertTrue(state.beginApplying(.init(document: document, pageSession: changedEnd)))
        XCTAssertTrue(state.finishApplying(.init(document: document, pageSession: changedEnd)))
        XCTAssertTrue(state.beginApplying(.init(document: document, pageSession: changedInitial)))
    }

    func testPageSessionRestoresAndClampsLastViewedPage() throws {
        let restored = try PDFViewerPageSession(
            startPageIndex: 2,
            endPageIndex: 5,
            lastViewedPageIndex: 4,
            documentPageCount: 8
        )
        let beforeRange = try PDFViewerPageSession(
            startPageIndex: 2,
            endPageIndex: 5,
            lastViewedPageIndex: 0,
            documentPageCount: 8
        )
        let afterRange = try PDFViewerPageSession(
            startPageIndex: 2,
            endPageIndex: 5,
            lastViewedPageIndex: 7,
            documentPageCount: 8
        )

        XCTAssertEqual(restored.initialPageIndex, 4)
        XCTAssertEqual(beforeRange.initialPageIndex, 2)
        XCTAssertEqual(afterRange.initialPageIndex, 5)
        XCTAssertEqual(restored.clamped(0), 2)
        XCTAssertEqual(restored.clamped(7), 5)
    }

    @MainActor
    func testLoaderRetriesAfterFailureAndUsesStoredMetadata() async throws {
        let pdfURL = try PDFTestFixture.make(pages: [
            "표지", "첫 페이지", "둘째 페이지", "셋째 페이지", "부록"
        ])
        defer { PDFTestFixture.remove(pdfURL) }

        let models = try makeModels(
            pageCount: 5,
            startPageIndex: 1,
            endPageIndex: 3
        )
        models.sheet.updateLastViewedPageIndex(2)

        let fileAccess = RetryStoredPDFAccessor(
            fileURL: pdfURL,
            failsFirstRequest: true
        )
        let loader = PDFViewerLoader(fileAccess: fileAccess)

        let firstResult = await loader.load(
            document: models.document,
            sheet: models.sheet
        )
        XCTAssertNil(firstResult)
        guard case .failed = loader.phase else {
            return XCTFail("첫 접근 실패가 오류 상태로 표시되어야 합니다.")
        }

        let secondResult = await loader.load(
            document: models.document,
            sheet: models.sheet
        )
        XCTAssertEqual(secondResult?.document.pageCount, 5)
        XCTAssertEqual(secondResult?.pageSession.initialPageIndex, 2)
        guard case .loaded = loader.phase else {
            return XCTFail("재시도 후 PDF가 열려야 합니다.")
        }

        let requests = await fileAccess.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy {
            $0.fileName == models.document.storedFileName
                && $0.checksum == models.document.checksum
        })
    }

    @MainActor
    func testLoaderRejectsNonFileURL() async throws {
        let models = try makeModels(
            pageCount: 2,
            startPageIndex: 0,
            endPageIndex: 1
        )
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/score.pdf"))
        let fileAccess = RetryStoredPDFAccessor(
            fileURL: remoteURL,
            failsFirstRequest: false
        )
        let loader = PDFViewerLoader(fileAccess: fileAccess)

        let result = await loader.load(
            document: models.document,
            sheet: models.sheet
        )

        XCTAssertNil(result)
        guard case .failed(let message) = loader.phase else {
            return XCTFail("안전하지 않은 URL은 오류 상태가 되어야 합니다.")
        }
        XCTAssertEqual(message, PDFViewerError.invalidStoredURL.localizedDescription)
    }

    @MainActor
    func testLoaderWithoutSheetOpensEntireDocumentFromFirstPage() async throws {
        let pdfURL = try PDFTestFixture.make(pages: [
            "표지", "첫 페이지", "둘째 페이지", "부록"
        ])
        defer { PDFTestFixture.remove(pdfURL) }

        let models = try makeModels(
            pageCount: 4,
            startPageIndex: 1,
            endPageIndex: 2
        )
        models.sheet.updateLastViewedPageIndex(2)
        let fileAccess = RetryStoredPDFAccessor(
            fileURL: pdfURL,
            failsFirstRequest: false
        )
        let loader = PDFViewerLoader(fileAccess: fileAccess)

        let result = await loader.load(
            document: models.document,
            sheet: nil
        )

        XCTAssertEqual(result?.pageSession.startPageIndex, 0)
        XCTAssertEqual(result?.pageSession.endPageIndex, 3)
        XCTAssertEqual(result?.pageSession.initialPageIndex, 0)
        XCTAssertEqual(models.sheet.lastViewedPageIndex, 2)
        XCTAssertNil(models.sheet.lastOpenedAt)
        XCTAssertNil(models.song.lastOpenedAt)
    }

    @MainActor
    func testCancelStopsActiveFileAccessAndKeepsLoaderIdle() async throws {
        let models = try makeModels(
            pageCount: 2,
            startPageIndex: 0,
            endPageIndex: 1
        )
        let fileAccess = SuspendingStoredPDFAccessor()
        let loader = PDFViewerLoader(fileAccess: fileAccess)

        let loadTask = Task {
            await loader.load(
                document: models.document,
                sheet: models.sheet
            )
        }
        await fileAccess.waitUntilStarted()

        loader.cancel()
        let result = await loadTask.value

        XCTAssertNil(result)
        guard case .idle = loader.phase else {
            return XCTFail("취소된 로더는 대기 상태로 돌아가야 합니다.")
        }
        let didObserveCancellation = await fileAccess.didObserveCancellation
        XCTAssertTrue(didObserveCancellation)
    }

    @MainActor
    func testSessionPersistenceSavesPageAndOpenTimestamps() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let models = try makeModels(
            pageCount: 4,
            startPageIndex: 1,
            endPageIndex: 3
        )
        context.insert(models.document)
        context.insert(models.song)
        context.insert(models.sheet)
        try context.save()

        let openedAt = Date(timeIntervalSince1970: 100)
        try PDFViewerSessionPersistence.recordOpened(
            sheet: models.sheet,
            pageIndex: 2,
            at: openedAt,
            in: context
        )

        XCTAssertEqual(models.sheet.lastViewedPageIndex, 2)
        XCTAssertEqual(models.sheet.lastOpenedAt, openedAt)
        XCTAssertEqual(models.song.lastOpenedAt, openedAt)

        let movedAt = Date(timeIntervalSince1970: 200)
        try PDFViewerSessionPersistence.recordPageChange(
            99,
            sheet: models.sheet,
            at: movedAt,
            in: context
        )

        let verificationContext = ModelContext(container)
        let savedSheets = try verificationContext.fetch(FetchDescriptor<SongSheet>())
        let savedSongs = try verificationContext.fetch(FetchDescriptor<Song>())
        XCTAssertEqual(savedSheets.first?.lastViewedPageIndex, 3)
        XCTAssertEqual(savedSheets.first?.lastOpenedAt, movedAt)
        XCTAssertEqual(savedSongs.first?.lastOpenedAt, movedAt)
    }

    @MainActor
    func testSessionPersistenceRestoresViewerChangesWhenSaveFails() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let models = try makeModels(
            pageCount: 4,
            startPageIndex: 1,
            endPageIndex: 3
        )
        context.insert(models.document)
        context.insert(models.song)
        context.insert(models.sheet)

        let originalOpenedAt = Date(timeIntervalSince1970: 50)
        models.sheet.updateLastViewedPageIndex(2)
        models.sheet.lastOpenedAt = originalOpenedAt
        models.song.lastOpenedAt = originalOpenedAt
        try context.save()

        XCTAssertThrowsError(
            try PDFViewerSessionPersistence.recordActivity(
                sheet: models.sheet,
                pageIndex: 3,
                at: Date(timeIntervalSince1970: 100),
                save: { throw StubSaveError.failed }
            )
        )

        XCTAssertEqual(models.sheet.lastViewedPageIndex, 2)
        XCTAssertEqual(models.sheet.lastOpenedAt, originalOpenedAt)
        XCTAssertEqual(models.song.lastOpenedAt, originalOpenedAt)

        // A later unrelated save must not persist the failed viewer update.
        models.song.notes = "후속 변경"
        try context.save()

        let verificationContext = ModelContext(container)
        let savedSheets = try verificationContext.fetch(FetchDescriptor<SongSheet>())
        let savedSongs = try verificationContext.fetch(FetchDescriptor<Song>())
        XCTAssertEqual(savedSheets.first?.lastViewedPageIndex, 2)
        XCTAssertEqual(savedSheets.first?.lastOpenedAt, originalOpenedAt)
        XCTAssertEqual(savedSongs.first?.lastOpenedAt, originalOpenedAt)
        XCTAssertEqual(savedSongs.first?.notes, "후속 변경")
    }

    @MainActor
    private func makeModels(
        pageCount: Int,
        startPageIndex: Int,
        endPageIndex: Int
    ) throws -> (
        document: ArchiveDocument,
        song: Song,
        sheet: SongSheet
    ) {
        let document = ArchiveDocument(
            originalFileName: "예배 악보.pdf",
            storedFileName: "11111111-1111-1111-1111-111111111111.pdf",
            pageCount: pageCount,
            fileSize: 1,
            checksum: "expected-checksum",
            analysisStatus: .completed
        )
        let song = Song(title: "테스트 찬양")
        let sheet = try SongSheet.create(
            startPageIndex: startPageIndex,
            endPageIndex: endPageIndex,
            document: document,
            song: song
        )
        return (document, song, sheet)
    }

    @MainActor
    private func currentPageIndex(in pdfView: PDFView) -> Int? {
        guard
            let document = pdfView.document,
            let currentPage = pdfView.currentPage
        else {
            return nil
        }
        return document.index(for: currentPage)
    }

    @MainActor
    private func waitForNextMainTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

private enum StubSaveError: Error {
    case failed
}

private actor RetryStoredPDFAccessor: StoredPDFAccessing {
    struct Request: Equatable, Sendable {
        let fileName: String
        let checksum: String
    }

    private let fileURL: URL
    private var shouldFail: Bool
    private var recordedRequests: [Request] = []

    init(fileURL: URL, failsFirstRequest: Bool) {
        self.fileURL = fileURL
        shouldFail = failsFirstRequest
    }

    func storedFileURL(
        named storedFileName: String,
        expectedChecksum: String
    ) async throws -> URL {
        recordedRequests.append(Request(
            fileName: storedFileName,
            checksum: expectedChecksum
        ))

        if shouldFail {
            shouldFail = false
            throw PDFFileStoreError.storedFileMissing
        }
        return fileURL
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

private actor SuspendingStoredPDFAccessor: StoredPDFAccessing {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var didObserveCancellation = false

    func storedFileURL(
        named storedFileName: String,
        expectedChecksum: String
    ) async throws -> URL {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        do {
            try await Task<Never, Never>.sleep(nanoseconds: 60_000_000_000)
        } catch is CancellationError {
            didObserveCancellation = true
            throw CancellationError()
        }

        throw PDFFileStoreError.storedFileMissing
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}
