import SwiftData
import XCTest
@testable import WorshipArchive

final class ArchiveLibraryEditingTests: XCTestCase {
    @MainActor
    func testUpdatesStoredSongAndSheet() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let document = makeDocument(name: "수정.pdf", pages: 3)
        let song = Song(title: "이전 제목", lyricsText: "이전 가사")
        let sheet = try SongSheet.create(
            startPageIndex: 0,
            endPageIndex: 0,
            document: document,
            song: song
        )
        context.insert(document)
        context.insert(song)
        context.insert(sheet)
        for index in 0..<3 {
            context.insert(try PageAnalysis.create(
                pageIndex: index,
                extractedText: "\(index + 1)페이지 가사",
                confidence: 1,
                status: .textExtracted,
                recognitionMethod: .embeddedText,
                document: document
            ))
        }
        try context.save()

        try ArchiveLibraryEditing.updateSong(
            song,
            title: " 새 제목 ",
            notes: " 메모 ",
            in: context
        )
        try ArchiveLibraryEditing.updateSheet(
            sheet,
            musicalKey: .gMajor,
            startPageNumber: 2,
            endPageNumber: 3,
            in: context
        )

        XCTAssertEqual(song.title, "새 제목")
        XCTAssertEqual(song.notes, "메모")
        XCTAssertEqual(sheet.musicalKey, .gMajor)
        XCTAssertEqual(sheet.startPageIndex, 1)
        XCTAssertEqual(sheet.endPageIndex, 2)
        XCTAssertTrue(sheet.recognizedText.contains("2페이지 가사"))
        XCTAssertFalse(sheet.recognizedText.contains("1페이지 가사"))
        XCTAssertEqual(song.lyricsText, sheet.recognizedText)
    }

    @MainActor
    func testDeletingDocumentKeepsSongWithAnotherSheetAndRemovesOrphanSong() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let firstDocument = makeDocument(name: "첫.pdf", pages: 1)
        let secondDocument = makeDocument(name: "둘.pdf", pages: 1)
        let sharedSong = Song(title: "공통 곡")
        let orphanSong = Song(title: "사라질 곡")
        let removedSheet = try SongSheet.create(
            startPageIndex: 0,
            endPageIndex: 0,
            recognizedText: "이전 가사",
            document: firstDocument,
            song: sharedSong
        )
        let keptSheet = try SongSheet.create(
            startPageIndex: 0,
            endPageIndex: 0,
            recognizedText: "남은 가사",
            document: secondDocument,
            song: sharedSong
        )
        let orphanSheet = try SongSheet.create(
            startPageIndex: 0,
            endPageIndex: 0,
            document: firstDocument,
            song: orphanSong
        )
        [firstDocument, secondDocument].forEach(context.insert)
        [sharedSong, orphanSong].forEach(context.insert)
        [removedSheet, keptSheet, orphanSheet].forEach(context.insert)
        try context.save()

        let removedFileName = try ArchiveLibraryEditing.deleteDocument(
            firstDocument,
            in: context
        )

        XCTAssertEqual(removedFileName, firstDocument.storedFileName)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ArchiveDocument>()).count, 1)
        let songs = try context.fetch(FetchDescriptor<Song>())
        XCTAssertEqual(songs.map(\.title), ["공통 곡"])
        XCTAssertEqual(songs.first?.lyricsText, "남은 가사")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SongSheet>()).count, 1)
    }

    @MainActor
    private func makeDocument(name: String, pages: Int) -> ArchiveDocument {
        ArchiveDocument(
            originalFileName: name,
            storedFileName: "\(UUID().uuidString.lowercased()).pdf",
            pageCount: pages,
            fileSize: 100,
            checksum: UUID().uuidString,
            analysisStatus: .completed
        )
    }
}
