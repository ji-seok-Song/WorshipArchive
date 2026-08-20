import CryptoKit
import Foundation
import PDFKit
import XCTest
@testable import WorshipArchive

@MainActor
final class CloudBackedPDFFileStoreTests: XCTestCase {
    func testValidLocalPDFIsReturnedWithoutCallingRemote() async throws {
        let sourceURL = try PDFTestFixture.make(pages: ["로컬 악보"])
        let rootDirectory = makeRootDirectory()
        defer {
            PDFTestFixture.remove(sourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let localStore = LocalPDFFileStore(rootDirectory: rootDirectory)
        let stagedPDF = try await localStore.stagePDF(from: sourceURL)
        let storedPDF = try await localStore.commit(stagedPDF)
        await localStore.discard(stagedPDF)
        let remote = FakePDFAssetRemote(
            sourceURL: sourceURL,
            metadata: try metadata(for: sourceURL)
        )
        let store = CloudBackedPDFFileStore(
            localFileStore: localStore,
            remote: remote
        )

        let fileURL = try await store.storedFileURL(
            named: storedPDF.storedFileName,
            expectedChecksum: storedPDF.checksum
        )

        XCTAssertEqual(fileURL.lastPathComponent, storedPDF.storedFileName)
        let downloadCount = await remote.downloadCallCount()
        XCTAssertEqual(downloadCount, 0)
    }

    func testMissingLocalPDFDownloadsAndInstallsValidatedRemoteAsset() async throws {
        let sourceURL = try PDFTestFixture.make(pages: ["첫 장", "둘째 장"])
        let rootDirectory = makeRootDirectory()
        defer {
            PDFTestFixture.remove(sourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let metadata = try metadata(for: sourceURL)
        let storedFileName = validStoredFileName()
        let remote = FakePDFAssetRemote(
            sourceURL: sourceURL,
            metadata: metadata
        )
        let store = CloudBackedPDFFileStore(
            localFileStore: LocalPDFFileStore(rootDirectory: rootDirectory),
            remote: remote
        )

        let installedURL = try await store.storedFileURL(
            named: storedFileName,
            expectedChecksum: metadata.checksum
        )

        XCTAssertEqual(installedURL.lastPathComponent, storedFileName)
        XCTAssertEqual(
            try Data(contentsOf: installedURL),
            try Data(contentsOf: sourceURL)
        )
        let downloadCount = await remote.downloadCallCount()
        XCTAssertEqual(downloadCount, 1)
    }

    func testDownloadedPDFIsReusedFromCacheWithoutSecondRemoteCall() async throws {
        let sourceURL = try PDFTestFixture.make(pages: ["캐시할 악보"])
        let rootDirectory = makeRootDirectory()
        defer {
            PDFTestFixture.remove(sourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let metadata = try metadata(for: sourceURL)
        let storedFileName = validStoredFileName()
        let remote = FakePDFAssetRemote(
            sourceURL: sourceURL,
            metadata: metadata
        )
        let store = CloudBackedPDFFileStore(
            localFileStore: LocalPDFFileStore(rootDirectory: rootDirectory),
            remote: remote
        )

        let firstURL = try await store.storedFileURL(
            named: storedFileName,
            expectedChecksum: metadata.checksum
        )
        let secondURL = try await store.storedFileURL(
            named: storedFileName,
            expectedChecksum: metadata.checksum
        )

        XCTAssertEqual(firstURL, secondURL)
        let downloadCount = await remote.downloadCallCount()
        XCTAssertEqual(downloadCount, 1)
    }

    func testConcurrentRequestsForSameChecksumShareOneDownload() async throws {
        let sourceURL = try PDFTestFixture.make(pages: ["동시 다운로드"])
        let rootDirectory = makeRootDirectory()
        defer {
            PDFTestFixture.remove(sourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let metadata = try metadata(for: sourceURL)
        let storedFileName = validStoredFileName()
        let remote = FakePDFAssetRemote(
            sourceURL: sourceURL,
            metadata: metadata,
            startsSuspended: true
        )
        let store = CloudBackedPDFFileStore(
            localFileStore: LocalPDFFileStore(rootDirectory: rootDirectory),
            remote: remote
        )

        let firstRequest = Task {
            try await store.storedFileURL(
                named: storedFileName,
                expectedChecksum: metadata.checksum
            )
        }
        await remote.waitUntilDownloadStarts()
        let secondRequest = Task {
            try await store.storedFileURL(
                named: storedFileName,
                expectedChecksum: metadata.checksum
            )
        }
        await Task.yield()
        await remote.resumeDownload()

        let firstURL = try await firstRequest.value
        let secondURL = try await secondRequest.value
        XCTAssertEqual(firstURL, secondURL)
        let downloadCount = await remote.downloadCallCount()
        XCTAssertEqual(downloadCount, 1)
    }

    func testWrongDownloadedChecksumLeavesNoStoredOrPartialFile() async throws {
        let expectedSourceURL = try PDFTestFixture.make(pages: ["기대한 악보"])
        let changedSourceURL = try PDFTestFixture.make(pages: ["변경된 악보"])
        let rootDirectory = makeRootDirectory()
        defer {
            PDFTestFixture.remove(expectedSourceURL)
            PDFTestFixture.remove(changedSourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let expectedMetadata = try metadata(for: expectedSourceURL)
        let remote = FakePDFAssetRemote(
            sourceURL: changedSourceURL,
            metadata: expectedMetadata
        )
        let store = CloudBackedPDFFileStore(
            localFileStore: LocalPDFFileStore(rootDirectory: rootDirectory),
            remote: remote
        )

        do {
            _ = try await store.storedFileURL(
                named: validStoredFileName(),
                expectedChecksum: expectedMetadata.checksum
            )
            XCTFail("checksum이 다른 PDF는 설치되면 안 됩니다.")
        } catch let error as PDFFileStoreError {
            XCTAssertEqual(error, .downloadedFileChanged)
        }

        XCTAssertEqual(try fileNames(in: rootDirectory.appending(path: "PDFs")), [])
        XCTAssertEqual(try fileNames(in: rootDirectory.appending(path: "Staging")), [])
    }

    func testChangedExistingFileIsNotOverwrittenByRemoteDownload() async throws {
        let sourceURL = try PDFTestFixture.make(pages: ["원래 악보"])
        let rootDirectory = makeRootDirectory()
        defer {
            PDFTestFixture.remove(sourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let localStore = LocalPDFFileStore(rootDirectory: rootDirectory)
        let stagedPDF = try await localStore.stagePDF(from: sourceURL)
        let storedPDF = try await localStore.commit(stagedPDF)
        await localStore.discard(stagedPDF)
        let storedURL = try await localStore.storedFileURL(
            named: storedPDF.storedFileName,
            expectedChecksum: storedPDF.checksum
        )
        let changedData = Data("not the original pdf".utf8)
        try changedData.write(to: storedURL, options: .atomic)

        let remote = FakePDFAssetRemote(
            sourceURL: sourceURL,
            metadata: try metadata(for: sourceURL)
        )
        let store = CloudBackedPDFFileStore(
            localFileStore: localStore,
            remote: remote
        )

        do {
            _ = try await store.storedFileURL(
                named: storedPDF.storedFileName,
                expectedChecksum: storedPDF.checksum
            )
            XCTFail("변조된 기존 파일을 원격 파일로 조용히 덮어쓰면 안 됩니다.")
        } catch let error as PDFFileStoreError {
            XCTAssertEqual(error, .storedFileChanged)
        }

        XCTAssertEqual(try Data(contentsOf: storedURL), changedData)
        let downloadCount = await remote.downloadCallCount()
        XCTAssertEqual(downloadCount, 0)
    }

    func testInstallDownloadedPDFDoesNotOverwriteDifferentExistingFile() async throws {
        let existingSourceURL = try PDFTestFixture.make(pages: ["기존 악보"])
        let incomingSourceURL = try PDFTestFixture.make(pages: ["새 악보"])
        let rootDirectory = makeRootDirectory()
        defer {
            PDFTestFixture.remove(existingSourceURL)
            PDFTestFixture.remove(incomingSourceURL)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let localStore = LocalPDFFileStore(rootDirectory: rootDirectory)
        let stagedPDF = try await localStore.stagePDF(from: existingSourceURL)
        let storedPDF = try await localStore.commit(stagedPDF)
        await localStore.discard(stagedPDF)
        let storedURL = try await localStore.storedFileURL(
            named: storedPDF.storedFileName,
            expectedChecksum: storedPDF.checksum
        )
        let existingData = try Data(contentsOf: storedURL)
        let incomingMetadata = try metadata(for: incomingSourceURL)

        do {
            _ = try await localStore.installDownloadedPDF(
                from: incomingSourceURL,
                named: storedPDF.storedFileName,
                expectedChecksum: incomingMetadata.checksum,
                expectedFileSize: incomingMetadata.fileSize,
                expectedPageCount: incomingMetadata.pageCount
            )
            XCTFail("다른 기존 파일을 덮어쓰면 안 됩니다.")
        } catch let error as PDFFileStoreError {
            XCTAssertEqual(error, .storedFileCollision)
        }

        XCTAssertEqual(try Data(contentsOf: storedURL), existingData)
    }

    private func makeRootDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "WorshipArchiveCloudCacheTest-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func validStoredFileName() -> String {
        "\(UUID().uuidString.lowercased()).pdf"
    }

    private func metadata(for fileURL: URL) throws -> RemotePDFAsset {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let pageCount = try XCTUnwrap(PDFDocument(url: fileURL)?.pageCount)
        return RemotePDFAsset(
            checksum: try sha256(of: fileURL),
            fileSize: Int64(values.fileSize ?? 0),
            pageCount: pageCount,
            revision: "test-revision"
        )
    }

    private func sha256(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func fileNames(in directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .sorted()
    }
}

private actor FakePDFAssetRemote: PDFAssetRemote {
    private let sourceURL: URL
    private let metadata: RemotePDFAsset
    private var isSuspended: Bool
    private var downloadCount = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        sourceURL: URL,
        metadata: RemotePDFAsset,
        startsSuspended: Bool = false
    ) {
        self.sourceURL = sourceURL
        self.metadata = metadata
        isSuspended = startsSuspended
    }

    func accountAvailability() async -> CloudAccountAvailability {
        .available
    }

    func upload(
        _ asset: LocalPDFAsset,
        fileURL: URL
    ) async throws -> PDFAssetUploadResult {
        .alreadyPresent(metadata)
    }

    func download(checksum: String) async throws -> DownloadedPDFAsset {
        downloadCount += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        if isSuspended {
            await withCheckedContinuation { continuation in
                resumeWaiters.append(continuation)
            }
        }

        let temporaryURL = FileManager.default.temporaryDirectory.appending(
            path: "WorshipArchiveRemoteDownload-\(UUID().uuidString).pdf"
        )
        try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
        return DownloadedPDFAsset(
            metadata: metadata,
            temporaryFileURL: temporaryURL
        )
    }

    func downloadCallCount() -> Int {
        downloadCount
    }

    func waitUntilDownloadStarts() async {
        guard downloadCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeDownload() {
        isSuspended = false
        let waiters = resumeWaiters
        resumeWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
