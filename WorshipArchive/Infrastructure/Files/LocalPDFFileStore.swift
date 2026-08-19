import CryptoKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

actor LocalPDFFileStore: PDFFileStoring {
    private let rootDirectory: URL

    private var fileManager: FileManager { .default }

    private var stagingDirectory: URL {
        rootDirectory.appending(path: "Staging", directoryHint: .isDirectory)
    }

    private var documentsDirectory: URL {
        rootDirectory.appending(path: "PDFs", directoryHint: .isDirectory)
    }

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    static func live() throws -> LocalPDFFileStore {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootDirectory = applicationSupport
            .appending(path: "WorshipArchive", directoryHint: .isDirectory)

        return LocalPDFFileStore(rootDirectory: rootDirectory)
    }

    func stagePDF(from sourceURL: URL) async throws -> StagedPDF {
        let accessedSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileResourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard fileResourceValues.isRegularFile == true else {
            throw PDFFileStoreError.sourceIsNotAFile
        }

        let contentType = try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        let isPDFContent = contentType?.conforms(to: .pdf) == true
        let hasPDFExtension = sourceURL.pathExtension.lowercased() == "pdf"
        guard isPDFContent || hasPDFExtension else {
            throw PDFFileStoreError.unsupportedFile
        }

        try createDirectoriesIfNeeded()

        let id = UUID()
        let stagingFileName = "\(id.uuidString.lowercased()).pdf"
        let stagingURL = stagingDirectory.appending(path: stagingFileName)

        do {
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            try updateModificationDate(of: stagingURL)
            let pageCount = try validatePDF(at: stagingURL)
            let checksum = try sha256(of: stagingURL)
            let fileSize = try sizeOfFile(at: stagingURL)

            return StagedPDF(
                id: id,
                originalFileName: sourceURL.lastPathComponent,
                stagingFileName: stagingFileName,
                checksum: checksum,
                fileSize: fileSize,
                pageCount: pageCount
            )
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    func commit(_ stagedPDF: StagedPDF) async throws -> StoredPDF {
        try createDirectoriesIfNeeded()

        guard isValidStagingFileName(stagedPDF.stagingFileName) else {
            throw PDFFileStoreError.invalidStagedFileName
        }
        let stagingURL = stagingDirectory.appending(path: stagedPDF.stagingFileName)
        guard fileManager.fileExists(atPath: stagingURL.path) else {
            throw PDFFileStoreError.stagedFileMissing
        }
        guard try sha256(of: stagingURL) == stagedPDF.checksum else {
            throw PDFFileStoreError.stagedFileChanged
        }

        let storedFileName = "\(stagedPDF.id.uuidString.lowercased()).pdf"
        let destinationURL = documentsDirectory.appending(path: storedFileName)

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw PDFFileStoreError.storedFileCollision
        }

        try updateModificationDate(of: stagingURL)
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        return StoredPDF(
            storedFileName: storedFileName,
            checksum: stagedPDF.checksum,
            fileSize: stagedPDF.fileSize,
            pageCount: stagedPDF.pageCount
        )
    }

    func discard(_ stagedPDF: StagedPDF) async {
        guard isValidStagingFileName(stagedPDF.stagingFileName) else { return }
        let stagingURL = stagingDirectory.appending(path: stagedPDF.stagingFileName)
        guard (try? isRegularFile(at: stagingURL)) == true else { return }
        try? fileManager.removeItem(at: stagingURL)
    }

    func storedFileURL(
        named storedFileName: String,
        expectedChecksum: String
    ) async throws -> URL {
        guard isValidStoredFileName(storedFileName) else {
            throw PDFFileStoreError.invalidStoredFileName
        }

        let fileURL = documentsDirectory.appending(path: storedFileName)
        guard try isRegularFile(at: fileURL) else {
            throw PDFFileStoreError.storedFileMissing
        }
        guard try sha256(of: fileURL) == expectedChecksum else {
            throw PDFFileStoreError.storedFileChanged
        }
        return fileURL
    }

    func removeStoredFile(named storedFileName: String) async throws {
        guard isValidStoredFileName(storedFileName) else {
            throw PDFFileStoreError.invalidStoredFileName
        }
        let fileURL = documentsDirectory.appending(path: storedFileName)
        guard try isRegularFile(at: fileURL) else {
            throw PDFFileStoreError.storedFileMissing
        }
        try fileManager.removeItem(at: fileURL)
    }

    func removeStaleStagedFiles(olderThan cutoffDate: Date) async throws {
        try createDirectoriesIfNeeded()
        let stagedFiles = try fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for fileURL in stagedFiles {
            let resourceValues = try fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
            guard resourceValues.isRegularFile == true else { continue }
            guard let modifiedAt = resourceValues.contentModificationDate else { continue }
            guard modifiedAt < cutoffDate else { continue }
            try fileManager.removeItem(at: fileURL)
        }
    }

    func removeUnreferencedStoredFiles(
        keeping referencedFileNames: Set<String>,
        olderThan cutoffDate: Date
    ) async throws {
        try createDirectoriesIfNeeded()
        let storedFiles = try fileManager.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for fileURL in storedFiles {
            let fileName = fileURL.lastPathComponent
            guard isValidStoredFileName(fileName) else { continue }
            guard !referencedFileNames.contains(fileName) else { continue }

            let resourceValues = try fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
            guard resourceValues.isRegularFile == true else { continue }
            guard let modifiedAt = resourceValues.contentModificationDate else { continue }
            guard modifiedAt < cutoffDate else { continue }
            try fileManager.removeItem(at: fileURL)
        }
    }

    private func createDirectoriesIfNeeded() throws {
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: documentsDirectory,
            withIntermediateDirectories: true
        )
    }

    private func sha256(of fileURL: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        while let data = try fileHandle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func sizeOfFile(at fileURL: URL) throws -> Int64 {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func updateModificationDate(of fileURL: URL) throws {
        try fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }

    private func validatePDF(at fileURL: URL) throws -> Int {
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else {
            throw PDFFileStoreError.invalidPDFDocument
        }
        return document.pageCount
    }

    private func isRegularFile(at fileURL: URL) throws -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else { return false }
        return try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
    }

    private func isValidStoredFileName(_ fileName: String) -> Bool {
        isValidUUIDFileName(fileName)
    }

    private func isValidStagingFileName(_ fileName: String) -> Bool {
        isValidUUIDFileName(fileName)
    }

    private func isValidUUIDFileName(_ fileName: String) -> Bool {
        guard fileName.hasSuffix(".pdf") else { return false }
        let identifier = String(fileName.dropLast(4))
        return UUID(uuidString: identifier) != nil
    }
}
