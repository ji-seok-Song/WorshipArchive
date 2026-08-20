import Foundation
import SwiftData
import XCTest
@testable import WorshipArchive

final class ArchiveResilienceTests: XCTestCase {
    @MainActor
    func testStoredPDFChecksumRejectsFileChangedAfterCommit() async throws {
        let sourceURL = try PDFTestFixture.make(pages: [
            "무결성 확인 찬양\n보관된 원본이 바뀌면 열지 않아야 합니다"
        ])
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "WorshipArchiveChecksumTest-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer {
            PDFTestFixture.remove(sourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let fileStore = LocalPDFFileStore(rootDirectory: rootDirectory)
        let stagedPDF = try await fileStore.stagePDF(from: sourceURL)
        let storedPDF = try await fileStore.commit(stagedPDF)
        let storedFileURL = try await fileStore.storedFileURL(
            named: storedPDF.storedFileName,
            expectedChecksum: storedPDF.checksum
        )

        do {
            let fileHandle = try FileHandle(forWritingTo: storedFileURL)
            defer { try? fileHandle.close() }
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: Data("\n% changed after commit".utf8))
        }

        do {
            _ = try await fileStore.storedFileURL(
                named: storedPDF.storedFileName,
                expectedChecksum: storedPDF.checksum
            )
            XCTFail("변조된 원본 PDF는 뷰어에 전달되면 안 됩니다.")
        } catch let error as PDFFileStoreError {
            XCTAssertEqual(error, .storedFileChanged)
        } catch {
            XCTFail("예상하지 못한 오류입니다: \(error)")
        }
    }

    @MainActor
    func testDiskStoreReopensArchiveRelationshipsAndViewerState() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "WorshipArchiveReopenTest-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let storeURL = rootDirectory.appending(path: "Archive.store")
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        let expected = try autoreleasepool {
            try persistArchiveFixture(to: storeURL)
        }

        // The first container and context have left scope before reopening this URL.
        let reopenedContainer = try makeDiskContainer(at: storeURL)
        let context = ModelContext(reopenedContainer)
        let documents = try context.fetch(FetchDescriptor<ArchiveDocument>())
        let songs = try context.fetch(FetchDescriptor<Song>())
        let sheets = try context.fetch(FetchDescriptor<SongSheet>())
        let records = try context.fetch(FetchDescriptor<PerformanceRecord>())

        let document = try XCTUnwrap(documents.first)
        let song = try XCTUnwrap(songs.first)
        let sheet = try XCTUnwrap(sheets.first)
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(sheets.count, 1)
        XCTAssertEqual(records.count, 1)

        XCTAssertEqual(document.id, expected.documentID)
        XCTAssertEqual(document.analysisStatus, .completed)
        XCTAssertEqual(document.sheets?.map(\.id), [expected.sheetID])

        XCTAssertEqual(song.id, expected.songID)
        XCTAssertEqual(song.title, "다시 여는 찬양")
        XCTAssertEqual(song.lastOpenedAt, expected.openedAt)
        XCTAssertEqual(song.sheets?.map(\.id), [expected.sheetID])
        XCTAssertEqual(song.performanceRecords?.map(\.id), [expected.recordID])

        XCTAssertEqual(sheet.id, expected.sheetID)
        XCTAssertEqual(sheet.document?.id, expected.documentID)
        XCTAssertEqual(sheet.song?.id, expected.songID)
        XCTAssertEqual(sheet.startPageIndex, 1)
        XCTAssertEqual(sheet.endPageIndex, 3)
        XCTAssertEqual(sheet.musicalKey, .gMajor)
        XCTAssertEqual(sheet.lastViewedPageIndex, 2)
        XCTAssertEqual(sheet.lastOpenedAt, expected.openedAt)

        XCTAssertEqual(record.id, expected.recordID)
        XCTAssertEqual(record.song?.id, expected.songID)
        XCTAssertEqual(record.performedAt, expected.performedAt)
        XCTAssertEqual(record.serviceType, "주일예배")
        XCTAssertEqual(record.leader, "이인도")
        XCTAssertEqual(record.musicalKey, .gMajor)
        XCTAssertEqual(record.notes, "재시작 후에도 보존할 기록")
    }

    @MainActor
    private func persistArchiveFixture(
        to storeURL: URL
    ) throws -> PersistedArchiveFixture {
        let container = try makeDiskContainer(at: storeURL)
        let context = ModelContext(container)
        let openedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let performedAt = Date(timeIntervalSince1970: 1_799_000_000)

        let document = ArchiveDocument(
            originalFileName: "재시작 예배 악보.pdf",
            storedFileName: "11111111-2222-3333-4444-555555555555.pdf",
            importedAt: Date(timeIntervalSince1970: 1_798_000_000),
            pageCount: 5,
            fileSize: 4_096,
            checksum: "restart-checksum",
            analysisStatus: .completed
        )
        let song = Song(
            title: "다시 여는 찬양",
            lyricsText: "관계와 열람 상태를 다시 불러옵니다",
            notes: "디스크 재개방 회귀 테스트",
            isFavorite: true,
            createdAt: Date(timeIntervalSince1970: 1_798_000_100)
        )
        let sheet = try SongSheet.create(
            startPageIndex: 1,
            endPageIndex: 3,
            musicalKey: .gMajor,
            recognizedText: "관계와 열람 상태를 다시 불러옵니다",
            createdAt: Date(timeIntervalSince1970: 1_798_000_200),
            document: document,
            song: song
        )
        sheet.updateLastViewedPageIndex(2)
        sheet.lastOpenedAt = openedAt
        song.lastOpenedAt = openedAt

        let record = PerformanceRecord(
            performedAt: performedAt,
            serviceType: "주일예배",
            leader: "이인도",
            musicalKey: .gMajor,
            notes: "재시작 후에도 보존할 기록",
            song: song
        )

        context.insert(document)
        context.insert(song)
        context.insert(sheet)
        context.insert(record)
        try context.save()

        return PersistedArchiveFixture(
            documentID: document.id,
            songID: song.id,
            sheetID: sheet.id,
            recordID: record.id,
            openedAt: openedAt,
            performedAt: performedAt
        )
    }

    @MainActor
    private func makeDiskContainer(at storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "WorshipArchiveResilience",
            schema: AppModelContainer.schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: AppModelContainer.schema,
            configurations: [configuration]
        )
    }
}

private struct PersistedArchiveFixture {
    let documentID: UUID
    let songID: UUID
    let sheetID: UUID
    let recordID: UUID
    let openedAt: Date
    let performedAt: Date
}
