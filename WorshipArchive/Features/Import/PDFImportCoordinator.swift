import Foundation
import Observation
import SwiftData

actor PDFImportReservation {
    static let shared = PDFImportReservation()

    private var checksums: Set<String> = []

    func reserve(_ checksum: String) -> Bool {
        checksums.insert(checksum).inserted
    }

    func release(_ checksum: String) {
        checksums.remove(checksum)
    }
}

@MainActor
@Observable
final class PDFImportCoordinator {
    enum Phase: Equatable {
        case selecting
        case staging
        case reviewing
        case saving
        case completed
    }

    private(set) var phase: Phase = .selecting
    private(set) var stagedPDF: StagedPDF?
    var drafts: [SongDraft] = []
    var errorMessage: String?

    @ObservationIgnored
    private let fileStore: any PDFFileStoring
    @ObservationIgnored
    private let importReservation: PDFImportReservation
    @ObservationIgnored
    private var stagingOperationID: UUID?
    @ObservationIgnored
    private var reservedChecksum: String?

    init(
        fileStore: any PDFFileStoring,
        importReservation: PDFImportReservation = .shared
    ) {
        self.fileStore = fileStore
        self.importReservation = importReservation
    }

    var canSave: Bool {
        guard phase == .reviewing, let stagedPDF else { return false }
        return (try? SongDraftValidator.validate(
            drafts,
            documentPageCount: stagedPDF.pageCount
        )) != nil
    }

    var hasPendingImport: Bool {
        stagedPDF != nil || phase == .staging || phase == .saving
    }

    var validationMessage: String? {
        guard phase == .reviewing, let stagedPDF else { return nil }

        do {
            _ = try SongDraftValidator.validate(
                drafts,
                documentPageCount: stagedPDF.pageCount
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func stagePDF(
        from sourceURL: URL,
        in modelContainer: ModelContainer
    ) async {
        guard phase != .saving else { return }

        let operationID = UUID()
        stagingOperationID = operationID

        let previousStagedPDF = stagedPDF
        let previousDrafts = drafts
        let previousChecksum = reservedChecksum
        var candidatePDF: StagedPDF?
        var didReserveCandidate = false

        phase = .staging

        do {
            let stagedPDF = try await fileStore.stagePDF(from: sourceURL)
            candidatePDF = stagedPDF

            guard stagingOperationID == operationID else {
                await fileStore.discard(stagedPDF)
                return
            }

            let context = ModelContext(modelContainer)
            try ensureDocumentIsNotDuplicate(
                checksum: stagedPDF.checksum,
                in: context
            )

            if stagedPDF.checksum != previousChecksum {
                guard await importReservation.reserve(stagedPDF.checksum) else {
                    throw PDFImportValidationError.duplicateImportInProgress
                }
                didReserveCandidate = true
            }

            guard stagingOperationID == operationID else {
                if didReserveCandidate {
                    await importReservation.release(stagedPDF.checksum)
                }
                await fileStore.discard(stagedPDF)
                return
            }

            self.stagedPDF = stagedPDF
            reservedChecksum = stagedPDF.checksum
            drafts = [
                SongDraft(
                    title: sourceURL.deletingPathExtension().lastPathComponent,
                    startPageNumber: 1,
                    endPageNumber: stagedPDF.pageCount
                )
            ]
            stagingOperationID = nil
            phase = .reviewing

            if let previousStagedPDF {
                await fileStore.discard(previousStagedPDF)
            }
            if let previousChecksum, previousChecksum != stagedPDF.checksum {
                await importReservation.release(previousChecksum)
            }
        } catch {
            if let candidatePDF {
                await fileStore.discard(candidatePDF)
            }

            guard stagingOperationID == operationID else { return }

            self.stagedPDF = previousStagedPDF
            drafts = previousDrafts
            reservedChecksum = previousChecksum
            stagingOperationID = nil
            phase = previousStagedPDF == nil ? .selecting : .reviewing
            errorMessage = error.localizedDescription
        }
    }

    func addSongDraft() {
        guard let stagedPDF else { return }

        if let unusedPage = firstUnusedPage(upTo: stagedPDF.pageCount) {
            drafts.append(
                SongDraft(
                    title: "새 찬양 \(drafts.count + 1)",
                    startPageNumber: unusedPage,
                    endPageNumber: unusedPage
                )
            )
            return
        }

        if let splitIndex = longestSplittableDraftIndex(
            documentPageCount: stagedPDF.pageCount
        ) {
            let originalEndPage = drafts[splitIndex].endPageNumber
            let pageCount = originalEndPage - drafts[splitIndex].startPageNumber + 1
            let newStartPage = drafts[splitIndex].startPageNumber + pageCount / 2
            drafts[splitIndex].endPageNumber = newStartPage - 1
            drafts.insert(
                SongDraft(
                    title: "새 찬양 \(drafts.count + 1)",
                    startPageNumber: newStartPage,
                    endPageNumber: originalEndPage
                ),
                at: splitIndex + 1
            )
            return
        }

        drafts.append(
            SongDraft(
                title: "새 찬양 \(drafts.count + 1)",
                startPageNumber: stagedPDF.pageCount,
                endPageNumber: stagedPDF.pageCount
            )
        )
    }

    func removeSongDraft(id: UUID) {
        drafts.removeAll { $0.id == id }
    }

    func previewURL() async -> URL? {
        guard phase == .reviewing, let stagedPDF else { return nil }

        do {
            return try await fileStore.stagedFileURL(for: stagedPDF)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func save(in modelContainer: ModelContainer) async -> Bool {
        guard phase == .reviewing else { return false }
        guard let stagedPDF else {
            errorMessage = PDFImportValidationError.missingStagedPDF.localizedDescription
            return false
        }

        let validatedDrafts: [ValidatedSongDraft]
        do {
            validatedDrafts = try SongDraftValidator.validate(
                drafts,
                documentPageCount: stagedPDF.pageCount
            )
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        phase = .saving
        let context = ModelContext(modelContainer)
        var committedPDF: StoredPDF?

        do {
            try ensureDocumentIsNotDuplicate(
                checksum: stagedPDF.checksum,
                in: context
            )

            let storedPDF = try await fileStore.commit(stagedPDF)
            committedPDF = storedPDF

            let document = ArchiveDocument(
                originalFileName: stagedPDF.originalFileName,
                storedFileName: storedPDF.storedFileName,
                pageCount: storedPDF.pageCount,
                fileSize: storedPDF.fileSize,
                checksum: storedPDF.checksum,
                analysisStatus: .pending
            )
            context.insert(document)

            for draft in validatedDrafts {
                let song = Song(title: draft.title)
                let sheet = try SongSheet.create(
                    startPageIndex: draft.pageRange.startPageIndex,
                    endPageIndex: draft.pageRange.endPageIndex,
                    musicalKey: draft.musicalKey,
                    document: document,
                    song: song
                )
                context.insert(song)
                context.insert(sheet)
            }

            try context.save()
            await fileStore.discard(stagedPDF)
            await releaseReservation()
            self.stagedPDF = nil
            drafts = []
            phase = .completed
            return true
        } catch {
            context.rollback()

            var cleanupFailureMessage: String?
            if let committedPDF {
                do {
                    try await fileStore.removeStoredFile(
                        named: committedPDF.storedFileName
                    )
                } catch PDFFileStoreError.storedFileMissing {
                    // The intended rollback result is already satisfied.
                } catch {
                    cleanupFailureMessage = "보관 파일 정리가 끝나지 않았습니다. 다시 저장하면 이어서 처리합니다."
                }
            }

            phase = .reviewing
            errorMessage = [error.localizedDescription, cleanupFailureMessage]
                .compactMap { $0 }
                .joined(separator: "\n")
            return false
        }
    }

    func cancel() async {
        guard phase != .saving else { return }

        stagingOperationID = nil
        let stagedPDF = self.stagedPDF
        let reservedChecksum = self.reservedChecksum
        self.stagedPDF = nil
        self.reservedChecksum = nil
        drafts = []
        phase = .selecting

        if let stagedPDF {
            await fileStore.discard(stagedPDF)
        }
        if let reservedChecksum {
            await importReservation.release(reservedChecksum)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func longestSplittableDraftIndex(
        documentPageCount: Int
    ) -> Int? {
        drafts.indices
            .filter { index in
                let draft = drafts[index]
                return (1...documentPageCount).contains(draft.startPageNumber)
                    && (1...documentPageCount).contains(draft.endPageNumber)
                    && draft.endPageNumber > draft.startPageNumber
            }
            .max { lhs, rhs in
                let lhsCount = drafts[lhs].endPageNumber - drafts[lhs].startPageNumber
                let rhsCount = drafts[rhs].endPageNumber - drafts[rhs].startPageNumber
                return lhsCount < rhsCount
            }
    }

    private func firstUnusedPage(upTo pageCount: Int) -> Int? {
        (1...pageCount).first { pageNumber in
            !drafts.contains { draft in
                draft.startPageNumber <= pageNumber
                    && pageNumber <= draft.endPageNumber
            }
        }
    }

    private func releaseReservation() async {
        guard let reservedChecksum else { return }
        self.reservedChecksum = nil
        await importReservation.release(reservedChecksum)
    }

    private func ensureDocumentIsNotDuplicate(
        checksum: String,
        in context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<ArchiveDocument>(
            predicate: #Predicate { document in
                document.checksum == checksum
            }
        )

        if let existingDocument = try context.fetch(descriptor).first {
            throw PDFImportValidationError.duplicateDocument(
                existingDocument.originalFileName
            )
        }
    }
}
