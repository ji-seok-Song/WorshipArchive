import PDFKit
import XCTest
@testable import WorshipArchive

final class SongPDFExporterTests: XCTestCase {
    func testExportsOnlyRequestedSongPagesAndRemovesTemporaryFile() async throws {
        let sourceURL = try PDFTestFixture.make(pages: [
            "첫째 페이지",
            "둘째 페이지",
            "셋째 페이지",
            "넷째 페이지"
        ])
        let exportRoot = FileManager.default.temporaryDirectory
            .appending(path: "SongPDFExporterTests-(UUID().uuidString)")
        defer {
            PDFTestFixture.remove(sourceURL)
            try? FileManager.default.removeItem(at: exportRoot)
        }

        let exporter = SongPDFExporter(
            fileAccess: ExportSourceAccessor(fileURL: sourceURL),
            exportRootDirectory: exportRoot
        )
        let exportedPDF = try await exporter.export(
            SongPDFExportRequest(
                storedFileName: "source.pdf",
                checksum: "checksum",
                expectedPageCount: 4,
                startPageIndex: 1,
                endPageIndex: 2,
                suggestedFileName: "나의/찬양: G.pdf"
            )
        )

        let document = try XCTUnwrap(PDFDocument(url: exportedPDF.fileURL))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("둘째 페이지") == true)
        XCTAssertTrue(document.page(at: 1)?.string?.contains("셋째 페이지") == true)
        XCTAssertFalse(exportedPDF.fileURL.lastPathComponent.contains("/"))
        XCTAssertFalse(exportedPDF.fileURL.lastPathComponent.contains(":"))

        await exporter.remove(exportedPDF)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: exportedPDF.directoryURL.path)
        )
    }

    func testRejectsInvalidSongPageRange() async throws {
        let sourceURL = try PDFTestFixture.make(pages: ["한 페이지"])
        defer { PDFTestFixture.remove(sourceURL) }
        let exporter = SongPDFExporter(
            fileAccess: ExportSourceAccessor(fileURL: sourceURL)
        )

        do {
            _ = try await exporter.export(
                SongPDFExportRequest(
                    storedFileName: "source.pdf",
                    checksum: "checksum",
                    expectedPageCount: 1,
                    startPageIndex: 1,
                    endPageIndex: 1,
                    suggestedFileName: "잘못된 범위"
                )
            )
            XCTFail("문서 밖의 페이지 범위는 내보내면 안 됩니다.")
        } catch let error as SongPDFExportError {
            XCTAssertEqual(error, .invalidPageRange)
        }
    }

    func testRejectsSourceWhosePageCountChanged() async throws {
        let sourceURL = try PDFTestFixture.make(pages: ["첫째", "둘째"])
        defer { PDFTestFixture.remove(sourceURL) }
        let exporter = SongPDFExporter(
            fileAccess: ExportSourceAccessor(fileURL: sourceURL)
        )

        do {
            _ = try await exporter.export(
                SongPDFExportRequest(
                    storedFileName: "source.pdf",
                    checksum: "checksum",
                    expectedPageCount: 3,
                    startPageIndex: 0,
                    endPageIndex: 1,
                    suggestedFileName: "페이지 변경"
                )
            )
            XCTFail("페이지 수가 달라진 원본은 내보내면 안 됩니다.")
        } catch let error as SongPDFExportError {
            XCTAssertEqual(error, .pageCountChanged)
        }
    }
}

private actor ExportSourceAccessor: StoredPDFAccessing {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func storedFileURL(
        named storedFileName: String,
        expectedChecksum: String
    ) async throws -> URL {
        fileURL
    }
}
