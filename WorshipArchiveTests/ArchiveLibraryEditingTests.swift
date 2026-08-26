import SwiftData
import XCTest
@testable import WorshipArchive

final class ArchiveLibraryEditingTests: XCTestCase {
    @MainActor
    func testUpdatesStoredSongAndSheet() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let document = makeDocument(name: "수정.pdf", pages: 3)
        let song = Song(title: "이전 제목")
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
    }

    @MainActor
    func testUpdatingKeyKeepsTheExistingPageRange() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let document = makeDocument(name: "키 수정.pdf", pages: 3)
        let song = Song(title: "키 수정 곡")
        let sheet = try SongSheet.create(
            startPageIndex: 1,
            endPageIndex: 2,
            musicalKey: .cMajor,
            document: document,
            song: song
        )
        context.insert(document)
        context.insert(song)
        context.insert(sheet)
        try context.save()

        try ArchiveLibraryEditing.updateSheetKey(
            sheet,
            musicalKey: .aMajor,
            in: context
        )

        XCTAssertEqual(sheet.musicalKey, .aMajor)
        XCTAssertEqual(sheet.startPageIndex, 1)
        XCTAssertEqual(sheet.endPageIndex, 2)
    }

    @MainActor
    func testDeletingSongKeepsTheOriginalDocument() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let document = makeDocument(name: "원본 유지.pdf", pages: 1)
        let song = Song(title: "삭제할 곡")
        let sheet = try SongSheet.create(
            startPageIndex: 0,
            endPageIndex: 0,
            document: document,
            song: song
        )
        context.insert(document)
        context.insert(song)
        context.insert(sheet)
        try context.save()

        try ArchiveLibraryEditing.deleteSong(song, in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Song>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SongSheet>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ArchiveDocument>()).count, 1)
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
        XCTAssertEqual(try context.fetch(FetchDescriptor<SongSheet>()).count, 1)
    }

    @MainActor
    func testMergingSongsMovesSheetsNotesAndFavorite() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let document = makeDocument(name: "병합.pdf", pages: 2)
        let target = Song(title: "대표 곡", notes: "대표 메모")
        let source = Song(
            title: "중복 곡",
            notes: "추가 메모",
            isFavorite: true
        )
        let targetSheet = try SongSheet.create(
            startPageIndex: 0,
            endPageIndex: 0,
            recognizedText: "대표 가사",
            document: document,
            song: target
        )
        let sourceSheet = try SongSheet.create(
            startPageIndex: 1,
            endPageIndex: 1,
            recognizedText: "추가 가사",
            document: document,
            song: source
        )
        context.insert(document)
        [target, source].forEach(context.insert)
        [targetSheet, sourceSheet].forEach(context.insert)
        try context.save()

        try ArchiveLibraryEditing.mergeSong(source, into: target, in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Song>()).count, 1)
        XCTAssertEqual(target.sheets?.count, 2)
        XCTAssertTrue(target.isFavorite)
        XCTAssertTrue(target.notes.contains("대표 메모"))
        XCTAssertTrue(target.notes.contains("추가 메모"))
        XCTAssertEqual(sourceSheet.song?.id, target.id)
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
