import Foundation

protocol PDFFileStoring: StoredPDFAccessing {
    func stagePDF(from sourceURL: URL) async throws -> StagedPDF
    func stagedFileURL(for stagedPDF: StagedPDF) async throws -> URL
    func commit(_ stagedPDF: StagedPDF) async throws -> StoredPDF
    func discard(_ stagedPDF: StagedPDF) async
    func removeStoredFile(named storedFileName: String) async throws
    func removeStaleStagedFiles(olderThan cutoffDate: Date) async throws
    func removeUnreferencedStoredFiles(
        keeping referencedFileNames: Set<String>,
        olderThan cutoffDate: Date
    ) async throws
}

enum PDFFileStoreError: LocalizedError, Equatable {
    case unsupportedFile
    case invalidPDFDocument
    case sourceIsNotAFile
    case stagedFileMissing
    case invalidStagedFileName
    case stagedFileChanged
    case storedFileChanged
    case storedFileCollision
    case invalidStoredFileName
    case storedFileMissing
    case downloadedFileChanged

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "PDF 파일만 가져올 수 있습니다."
        case .invalidPDFDocument:
            "열 수 있는 페이지가 있는 PDF가 아닙니다."
        case .sourceIsNotAFile:
            "선택한 항목을 파일로 읽을 수 없습니다."
        case .stagedFileMissing:
            "임시 보관 중인 PDF를 찾을 수 없습니다. 다시 선택해 주세요."
        case .invalidStagedFileName:
            "안전하지 않은 임시 PDF 경로가 감지되었습니다."
        case .stagedFileChanged:
            "임시 보관 중 PDF 내용이 변경되었습니다. 다시 선택해 주세요."
        case .storedFileChanged:
            "보관된 PDF의 무결성을 확인할 수 없습니다."
        case .storedFileCollision:
            "PDF 보관 경로가 이미 사용 중입니다. 다시 가져와 주세요."
        case .invalidStoredFileName:
            "안전하지 않은 PDF 경로가 감지되었습니다."
        case .storedFileMissing:
            "보관된 원본 PDF를 찾을 수 없습니다."
        case .downloadedFileChanged:
            "내려받은 PDF의 무결성을 확인할 수 없습니다."
        }
    }
}
