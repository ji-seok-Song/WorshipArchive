import SwiftData
import XCTest
@testable import WorshipArchive

@MainActor
final class CloudKitFoundationTests: XCTestCase {
    func testRegisteredContainerIdentifierIsUsedByTheApp() {
        XCTAssertEqual(
            AppModelContainer.cloudKitContainerIdentifier,
            "iCloud.com.jacky.WorshipArchive"
        )
    }

    func testInMemoryStoreStaysIndependentFromCloudKit() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let document = ArchiveDocument(
            originalFileName: "offline.pdf",
            storedFileName: "11111111-1111-1111-1111-111111111111.pdf",
            pageCount: 1,
            fileSize: 128,
            checksum: "local-checksum"
        )

        context.insert(document)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ArchiveDocument>())
        XCTAssertEqual(fetched.map(\.id), [document.id])
    }

    func testCloudKitConfigurationReopensExistingLocalStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let storeURL = directory.appending(path: "WorshipArchive.store")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let documentID = UUID()
        let songID = UUID()
        let sheetID = UUID()
        try saveLegacyArchive(
            at: storeURL,
            documentID: documentID,
            songID: songID,
            sheetID: sheetID
        )

        let cloudReadyContainer = try AppModelContainer.make(
            syncsWithCloudKit: true,
            storageURL: storeURL
        )
        let context = ModelContext(cloudReadyContainer)

        let documents = try context.fetch(FetchDescriptor<ArchiveDocument>())
        let songs = try context.fetch(FetchDescriptor<Song>())
        let sheets = try context.fetch(FetchDescriptor<SongSheet>())
        XCTAssertEqual(documents.map(\.id), [documentID])
        XCTAssertEqual(songs.map(\.id), [songID])
        XCTAssertEqual(sheets.map(\.id), [sheetID])
        XCTAssertEqual(sheets.first?.document?.id, documentID)
        XCTAssertEqual(sheets.first?.song?.id, songID)
    }

    private func saveLegacyArchive(
        at storeURL: URL,
        documentID: UUID,
        songID: UUID,
        sheetID: UUID
    ) throws {
        let container = try AppModelContainer.make(
            syncsWithCloudKit: false,
            storageURL: storeURL
        )
        let context = ModelContext(container)
        let document = ArchiveDocument(
            id: documentID,
            originalFileName: "legacy.pdf",
            storedFileName: "22222222-2222-2222-2222-222222222222.pdf",
            pageCount: 1,
            fileSize: 256,
            checksum: "legacy-checksum"
        )
        let song = Song(id: songID, title: "기존 찬양")
        let sheet = try SongSheet.create(
            id: sheetID,
            startPageIndex: 0,
            endPageIndex: 0,
            document: document,
            song: song
        )

        context.insert(document)
        context.insert(song)
        context.insert(sheet)
        try context.save()
    }
}
