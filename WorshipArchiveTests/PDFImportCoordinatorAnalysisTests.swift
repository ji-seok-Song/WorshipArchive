import CoreGraphics
import SwiftData
import XCTest
@testable import WorshipArchive

final class PDFImportCoordinatorAnalysisTests: XCTestCase {
    @MainActor
    func testAnalyzedImportPersistsPagesSongsAndSearchableText() async throws {
        let sourceURL = try PDFTestFixture.make(pages: [
            "첫 번째 찬양\n주의 사랑을 영원히 노래하며 기쁨으로 예배합니다",
            "두 번째 찬양\n온 마음을 다하여 주님의 이름을 높여 찬양합니다"
        ])
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "WorshipArchiveImportTest-\(UUID().uuidString)")
        defer {
            PDFTestFixture.remove(sourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let fileStore = LocalPDFFileStore(rootDirectory: rootDirectory)
        let analyzer = LocalPDFAnalyzer(textRecognizer: NeverCalledRecognizer())
        let coordinator = PDFImportCoordinator(
            fileStore: fileStore,
            pdfAnalyzer: analyzer,
            importReservation: PDFImportReservation()
        )
        let container = try AppModelContainer.make(inMemory: true)
        let seedContext = ModelContext(container)
        let existingSong = Song(title: "이미 저장된 찬양", lyricsText: "기존 가사")
        seedContext.insert(existingSong)
        try seedContext.save()

        await coordinator.stagePDF(from: sourceURL, in: container)

        XCTAssertEqual(coordinator.phase, .reviewing)
        XCTAssertEqual(coordinator.analysisResult?.pages.count, 2)
        XCTAssertEqual(coordinator.drafts.count, 2)
        XCTAssertTrue(coordinator.canSave)
        coordinator.drafts[0].existingSongID = existingSong.id
        let didSave = await coordinator.save(in: container)
        XCTAssertTrue(didSave)

        let context = ModelContext(container)
        let documents = try context.fetch(FetchDescriptor<ArchiveDocument>())
        let pages = try context.fetch(FetchDescriptor<PageAnalysis>())
        let songs = try context.fetch(FetchDescriptor<Song>())
        let sheets = try context.fetch(FetchDescriptor<SongSheet>())

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?.analysisStatus, .completed)
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages.allSatisfy { $0.recognitionMethod == .embeddedText })
        XCTAssertEqual(songs.count, 2)
        XCTAssertEqual(sheets.count, 2)
        let updatedExistingSong = try XCTUnwrap(
            songs.first(where: { $0.id == existingSong.id })
        )
        XCTAssertEqual(updatedExistingSong.sheets?.count, 1)
        XCTAssertTrue(updatedExistingSong.lyricsText.contains("기존 가사"))
        XCTAssertTrue(updatedExistingSong.lyricsText.contains("주의 사랑"))
        XCTAssertTrue(songs.allSatisfy { !$0.lyricsText.isEmpty })
        XCTAssertTrue(sheets.allSatisfy { !$0.recognizedText.isEmpty })
    }
}

private actor NeverCalledRecognizer: PageTextRecognizing {
    func recognizeText(in image: CGImage) async throws -> RecognizedPageText {
        throw UnexpectedRecognitionError()
    }
}

private struct UnexpectedRecognitionError: Error {}
