import Foundation
import PDFKit

nonisolated struct SongPDFExportRequest: Equatable, Sendable {
    let storedFileName: String
    let checksum: String
    let expectedPageCount: Int
    let startPageIndex: Int
    let endPageIndex: Int
    let suggestedFileName: String
}

nonisolated struct ExportedSongPDF: Identifiable, Equatable, Sendable {
    let id: UUID
    let fileURL: URL
    let directoryURL: URL
}

actor SongPDFExporter {
    private let fileAccess: any StoredPDFAccessing
    private let exportRootDirectory: URL
    private let fileManager: FileManager

    init(
        fileAccess: any StoredPDFAccessing,
        exportRootDirectory: URL = FileManager.default.temporaryDirectory
            .appending(path: "WorshipArchiveExports", directoryHint: .isDirectory),
        fileManager: FileManager = .default
    ) {
        self.fileAccess = fileAccess
        self.exportRootDirectory = exportRootDirectory
        self.fileManager = fileManager
    }

    func export(_ request: SongPDFExportRequest) async throws -> ExportedSongPDF {
        guard
            request.expectedPageCount > 0,
            request.startPageIndex >= 0,
            request.startPageIndex <= request.endPageIndex,
            request.endPageIndex < request.expectedPageCount
        else {
            throw SongPDFExportError.invalidPageRange
        }

        let sourceURL = try await fileAccess.storedFileURL(
            named: request.storedFileName,
            expectedChecksum: request.checksum
        )
        try Task.checkCancellation()

        guard let sourceDocument = PDFDocument(url: sourceURL) else {
            throw SongPDFExportError.documentCannotBeOpened
        }
        guard sourceDocument.pageCount == request.expectedPageCount else {
            throw SongPDFExportError.pageCountChanged
        }

        let exportedDocument = PDFDocument()
        for pageIndex in request.startPageIndex...request.endPageIndex {
            try Task.checkCancellation()
            guard
                let sourcePage = sourceDocument.page(at: pageIndex),
                let copiedPage = sourcePage.copy() as? PDFPage
            else {
                throw SongPDFExportError.pageCannotBeCopied
            }
            exportedDocument.insert(copiedPage, at: exportedDocument.pageCount)
        }

        guard
            exportedDocument.pageCount == request.endPageIndex - request.startPageIndex + 1,
            let data = exportedDocument.dataRepresentation(),
            !data.isEmpty
        else {
            throw SongPDFExportError.outputCannotBeCreated
        }

        let exportID = UUID()
        let directoryURL = exportRootDirectory.appending(
            path: exportID.uuidString.lowercased(),
            directoryHint: .isDirectory
        )

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let fileURL = directoryURL.appending(
                path: safePDFFileName(from: request.suggestedFileName)
            )
            try data.write(to: fileURL, options: .atomic)
            try Task.checkCancellation()
            return ExportedSongPDF(
                id: exportID,
                fileURL: fileURL,
                directoryURL: directoryURL
            )
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
    }

    func remove(_ exportedPDF: ExportedSongPDF) {
        let expectedParent = exportRootDirectory.standardizedFileURL
        let actualParent = exportedPDF.directoryURL
            .deletingLastPathComponent()
            .standardizedFileURL
        guard actualParent == expectedParent else { return }
        try? fileManager.removeItem(at: exportedPDF.directoryURL)
    }

    private func safePDFFileName(from suggestedFileName: String) -> String {
        let trimmedName = suggestedFileName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let sourceName = trimmedName.lowercased().hasSuffix(".pdf")
            ? String(trimmedName.dropLast(4))
            : trimmedName
        let invalidCharacters = CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        let sanitizedScalars = sourceName.unicodeScalars.map { scalar -> Character in
            invalidCharacters.contains(scalar) ? "-" : Character(String(scalar))
        }
        let sanitized = String(sanitizedScalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitized.isEmpty ? "찬양 악보" : String(sanitized.prefix(80))
        return "\(baseName).pdf"
    }
}

nonisolated enum SongPDFExportError: LocalizedError, Equatable {
    case invalidPageRange
    case documentCannotBeOpened
    case pageCountChanged
    case pageCannotBeCopied
    case outputCannotBeCreated

    var errorDescription: String? {
        switch self {
        case .invalidPageRange:
            "곡의 페이지 범위가 올바르지 않습니다."
        case .documentCannotBeOpened:
            "원본 PDF를 열 수 없습니다."
        case .pageCountChanged:
            "원본 PDF의 페이지 수가 저장된 정보와 다릅니다."
        case .pageCannotBeCopied:
            "곡에 포함된 페이지를 복사할 수 없습니다."
        case .outputCannotBeCreated:
            "공유할 곡 PDF를 만들 수 없습니다."
        }
    }
}
