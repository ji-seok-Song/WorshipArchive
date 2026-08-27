import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

struct PDFImportRequest: Identifiable {
    let id = UUID()
    let sourceURL: URL?

    static let manual = PDFImportRequest(sourceURL: nil)
}

private actor ArchiveFileMaintenanceGate {
    static let shared = ArchiveFileMaintenanceGate()

    private var hasStarted = false

    func beginIfNeeded() -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }
}

@MainActor
@Observable
final class AppViewModel {
    var selection: AppDestination = .home
    var pdfImportRequest: PDFImportRequest?
    var incomingDocumentErrorMessage: String?

    @ObservationIgnored
    private var didPerformFileMaintenance = false

    func presentPDFPicker() {
        pdfImportRequest = .manual
    }

    func handleIncomingDocument(_ url: URL) {
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let isPDF = resourceType?.conforms(to: .pdf) == true
            || url.pathExtension.lowercased() == "pdf"

        guard url.isFileURL, isPDF else {
            incomingDocumentErrorMessage = "찬양서랍에는 PDF 파일만 추가할 수 있어요."
            return
        }

        guard pdfImportRequest == nil else {
            incomingDocumentErrorMessage = "현재 PDF 확인을 마친 뒤 다시 공유해 주세요."
            return
        }

        pdfImportRequest = PDFImportRequest(sourceURL: url)
    }

    func syncAssets(from documents: [ArchiveDocument]) -> [LocalPDFAsset] {
        documents.compactMap { document in
            guard
                !document.storedFileName.isEmpty,
                !document.checksum.isEmpty,
                document.fileSize >= 0,
                document.pageCount > 0
            else {
                return nil
            }
            return LocalPDFAsset(
                documentID: document.id,
                storedFileName: document.storedFileName,
                checksum: document.checksum,
                fileSize: document.fileSize,
                pageCount: document.pageCount
            )
        }
    }

    func performFileMaintenanceIfNeeded(
        documents: [ArchiveDocument],
        fileStore: any PDFFileStoring,
        usesCloudSync: Bool,
        isEnabled: Bool
    ) async {
        guard isEnabled, !didPerformFileMaintenance else { return }
        didPerformFileMaintenance = true
        guard await ArchiveFileMaintenanceGate.shared.beginIfNeeded() else { return }

        let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60)
        try? await fileStore.removeStaleStagedFiles(olderThan: cutoffDate)

        // CloudKit metadata may arrive after launch. Until that first import is
        // complete, an apparently unreferenced PDF can still be valid cloud data.
        guard !usesCloudSync else { return }

        let referencedFileNames = Set(documents.map(\.storedFileName))
        try? await fileStore.removeUnreferencedStoredFiles(
            keeping: referencedFileNames,
            olderThan: cutoffDate
        )
    }
}
