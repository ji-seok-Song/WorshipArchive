import CloudKit
import CryptoKit
import Foundation
import XCTest
@testable import WorshipArchive

final class CloudKitPDFAssetStoreTests: XCTestCase {
    func testUploadCreatesContentAddressedRecordInDedicatedZone() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let transport = FakeCloudKitPDFAssetTransport()
        let store = CloudKitPDFAssetStore(
            transport: transport,
            temporaryDirectory: fixture.directory
        )

        let result = try await store.upload(
            fixture.asset,
            fileURL: fixture.fileURL
        )

        XCTAssertEqual(
            result,
            .uploaded(
                RemotePDFAsset(
                    checksum: fixture.asset.checksum,
                    fileSize: fixture.asset.fileSize,
                    pageCount: fixture.asset.pageCount,
                    revision: "saved-revision"
                )
            )
        )
        let calls = await transport.calls()
        XCTAssertEqual(calls.ensuredZoneNames, ["WorshipArchivePDFAssets.v1"])
        XCTAssertEqual(calls.savedRecords.count, 1)
        let record = try XCTUnwrap(calls.savedRecords.first)
        XCTAssertEqual(record.recordType, "WAPDFAsset")
        XCTAssertEqual(record.recordName, fixture.asset.checksum)
        XCTAssertEqual(record.zoneName, "WorshipArchivePDFAssets.v1")
        XCTAssertEqual(record.checksum, fixture.asset.checksum)
        XCTAssertEqual(record.fileSize, fixture.asset.fileSize)
        XCTAssertEqual(record.pageCount, fixture.asset.pageCount)
        XCTAssertEqual(record.schemaVersion, 1)
        XCTAssertEqual(record.pdfFileURL, fixture.fileURL)
    }

    func testUploadReturnsAlreadyPresentWithoutSavingAgain() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let existing = record(
            for: fixture,
            revision: "existing-revision"
        )
        let transport = FakeCloudKitPDFAssetTransport(records: [existing])
        let store = CloudKitPDFAssetStore(transport: transport)

        let result = try await store.upload(
            fixture.asset,
            fileURL: fixture.fileURL
        )

        XCTAssertEqual(
            result,
            .alreadyPresent(
                RemotePDFAsset(
                    checksum: fixture.asset.checksum,
                    fileSize: fixture.asset.fileSize,
                    pageCount: fixture.asset.pageCount,
                    revision: "existing-revision"
                )
            )
        )
        let calls = await transport.calls()
        XCTAssertTrue(calls.savedRecords.isEmpty)
    }

    func testConcurrentCreateConflictIsIdempotentWhenMetadataMatches() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let winningRecord = record(
            for: fixture,
            revision: "winning-revision"
        )
        let transport = FakeCloudKitPDFAssetTransport(
            saveMode: .conflictWith(winningRecord)
        )
        let store = CloudKitPDFAssetStore(transport: transport)

        let result = try await store.upload(
            fixture.asset,
            fileURL: fixture.fileURL
        )

        XCTAssertEqual(
            result,
            .alreadyPresent(
                RemotePDFAsset(
                    checksum: fixture.asset.checksum,
                    fileSize: fixture.asset.fileSize,
                    pageCount: fixture.asset.pageCount,
                    revision: "winning-revision"
                )
            )
        )
        let calls = await transport.calls()
        XCTAssertEqual(calls.fetchCount, 2)
    }

    func testExistingRecordMetadataMismatchThrowsIntegrityConflict() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let mismatchedRecord = CloudKitPDFAssetRecord(
            recordType: CloudKitPDFAssetStore.recordType,
            recordName: fixture.asset.checksum,
            zoneName: CloudKitPDFAssetStore.zoneName,
            checksum: fixture.asset.checksum,
            fileSize: fixture.asset.fileSize,
            pageCount: fixture.asset.pageCount + 1,
            schemaVersion: CloudKitPDFAssetStore.schemaVersion,
            pdfFileURL: fixture.fileURL,
            revision: "mismatch"
        )
        let transport = FakeCloudKitPDFAssetTransport(records: [mismatchedRecord])
        let store = CloudKitPDFAssetStore(transport: transport)

        do {
            _ = try await store.upload(fixture.asset, fileURL: fixture.fileURL)
            XCTFail("메타데이터 충돌이 성공으로 처리됐습니다.")
        } catch {
            XCTAssertEqual(error as? PDFAssetRemoteError, .integrityConflict)
        }
        let calls = await transport.calls()
        XCTAssertTrue(calls.savedRecords.isEmpty)
    }

    func testDownloadReturnsOwnedTemporaryCopyWithVerifiedContent() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let existing = record(for: fixture, revision: "download-revision")
        let transport = FakeCloudKitPDFAssetTransport(records: [existing])
        let store = CloudKitPDFAssetStore(
            transport: transport,
            temporaryDirectory: fixture.directory
        )

        let downloaded = try await store.download(
            checksum: fixture.asset.checksum
        )
        defer { try? FileManager.default.removeItem(at: downloaded.temporaryFileURL) }

        XCTAssertNotEqual(downloaded.temporaryFileURL, fixture.fileURL)
        XCTAssertEqual(downloaded.metadata.checksum, fixture.asset.checksum)
        XCTAssertEqual(downloaded.metadata.fileSize, fixture.asset.fileSize)
        XCTAssertEqual(downloaded.metadata.pageCount, fixture.asset.pageCount)

        try FileManager.default.removeItem(at: fixture.fileURL)
        XCTAssertEqual(
            try Data(contentsOf: downloaded.temporaryFileURL),
            fixture.data
        )
    }

    func testDownloadRejectsAssetWhoseBytesDoNotMatchMetadata() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let otherURL = fixture.directory.appending(path: "other.pdf")
        try Data("different-content".utf8).write(to: otherURL)
        let corruptRecord = CloudKitPDFAssetRecord(
            recordType: CloudKitPDFAssetStore.recordType,
            recordName: fixture.asset.checksum,
            zoneName: CloudKitPDFAssetStore.zoneName,
            checksum: fixture.asset.checksum,
            fileSize: Int64(try Data(contentsOf: otherURL).count),
            pageCount: fixture.asset.pageCount,
            schemaVersion: CloudKitPDFAssetStore.schemaVersion,
            pdfFileURL: otherURL,
            revision: nil
        )
        let transport = FakeCloudKitPDFAssetTransport(records: [corruptRecord])
        let store = CloudKitPDFAssetStore(
            transport: transport,
            temporaryDirectory: fixture.directory
        )

        do {
            _ = try await store.download(checksum: fixture.asset.checksum)
            XCTFail("손상된 CKAsset이 성공으로 처리됐습니다.")
        } catch {
            XCTAssertEqual(error as? PDFAssetRemoteError, .integrityConflict)
        }
    }

    func testCloudKitErrorsMapToRetryableTypedErrors() {
        let offline = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.networkUnavailable.rawValue
        )
        let limited = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.requestRateLimited.rawValue,
            userInfo: [CKErrorRetryAfterKey: NSNumber(value: 42)]
        )
        let quota = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.quotaExceeded.rawValue
        )
        let account = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.notAuthenticated.rawValue
        )

        XCTAssertEqual(
            CloudKitPDFAssetStore.mapCloudKitError(offline),
            .offline
        )
        XCTAssertEqual(
            CloudKitPDFAssetStore.mapCloudKitError(limited),
            .rateLimited(retryAfter: 42)
        )
        XCTAssertEqual(
            CloudKitPDFAssetStore.mapCloudKitError(quota),
            .quotaExceeded
        )
        XCTAssertEqual(
            CloudKitPDFAssetStore.mapCloudKitError(account),
            .accountUnavailable(.noAccount)
        )
    }

    func testAccountAvailabilityUsesTransportWithoutTouchingDatabase() async {
        let transport = FakeCloudKitPDFAssetTransport(
            accountAvailability: .restricted
        )
        let store = CloudKitPDFAssetStore(transport: transport)

        let availability = await store.accountAvailability()
        XCTAssertEqual(availability, .restricted)
        let calls = await transport.calls()
        XCTAssertTrue(calls.ensuredZoneNames.isEmpty)
        XCTAssertEqual(calls.fetchCount, 0)
        XCTAssertTrue(calls.savedRecords.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = Data("%PDF-cloudkit-fixture".utf8)
        let fileURL = directory.appending(path: "fixture.pdf")
        try data.write(to: fileURL)
        let checksum = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return Fixture(
            directory: directory,
            fileURL: fileURL,
            data: data,
            asset: LocalPDFAsset(
                documentID: UUID(),
                storedFileName: "fixture.pdf",
                checksum: checksum,
                fileSize: Int64(data.count),
                pageCount: 3
            )
        )
    }

    private func record(
        for fixture: Fixture,
        revision: String?
    ) -> CloudKitPDFAssetRecord {
        CloudKitPDFAssetRecord(
            recordType: CloudKitPDFAssetStore.recordType,
            recordName: fixture.asset.checksum,
            zoneName: CloudKitPDFAssetStore.zoneName,
            checksum: fixture.asset.checksum,
            fileSize: fixture.asset.fileSize,
            pageCount: fixture.asset.pageCount,
            schemaVersion: CloudKitPDFAssetStore.schemaVersion,
            pdfFileURL: fixture.fileURL,
            revision: revision
        )
    }
}

private nonisolated struct Fixture: Sendable {
    let directory: URL
    let fileURL: URL
    let data: Data
    let asset: LocalPDFAsset

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor FakeCloudKitPDFAssetTransport: CloudKitPDFAssetTransport {
    nonisolated enum SaveMode: Sendable {
        case save
        case conflictWith(CloudKitPDFAssetRecord)
    }

    nonisolated struct Calls: Sendable {
        let ensuredZoneNames: [String]
        let fetchCount: Int
        let savedRecords: [CloudKitPDFAssetRecord]
    }

    private let availability: CloudAccountAvailability
    private let saveMode: SaveMode
    private var recordsByName: [String: CloudKitPDFAssetRecord]
    private var ensuredZoneNames: [String] = []
    private var fetchCount = 0
    private var savedRecords: [CloudKitPDFAssetRecord] = []

    init(
        accountAvailability: CloudAccountAvailability = .available,
        records: [CloudKitPDFAssetRecord] = [],
        saveMode: SaveMode = .save
    ) {
        self.availability = accountAvailability
        self.saveMode = saveMode
        self.recordsByName = Dictionary(
            uniqueKeysWithValues: records.map { ($0.recordName, $0) }
        )
    }

    func accountAvailability() async throws -> CloudAccountAvailability {
        availability
    }

    func ensureZone(named zoneName: String) async throws {
        ensuredZoneNames.append(zoneName)
    }

    func fetchRecord(
        named recordName: String,
        recordType: String,
        zoneName: String
    ) async throws -> CloudKitPDFAssetRecord? {
        fetchCount += 1
        return recordsByName[recordName]
    }

    func saveIfAbsent(
        _ record: CloudKitPDFAssetRecord
    ) async throws -> CloudKitPDFAssetConditionalSaveResult {
        savedRecords.append(record)
        switch saveMode {
        case .save:
            let saved = CloudKitPDFAssetRecord(
                recordType: record.recordType,
                recordName: record.recordName,
                zoneName: record.zoneName,
                checksum: record.checksum,
                fileSize: record.fileSize,
                pageCount: record.pageCount,
                schemaVersion: record.schemaVersion,
                pdfFileURL: record.pdfFileURL,
                revision: "saved-revision"
            )
            recordsByName[record.recordName] = saved
            return .saved(saved)

        case let .conflictWith(winningRecord):
            recordsByName[winningRecord.recordName] = winningRecord
            return .recordAlreadyExists
        }
    }

    func calls() -> Calls {
        Calls(
            ensuredZoneNames: ensuredZoneNames,
            fetchCount: fetchCount,
            savedRecords: savedRecords
        )
    }
}
