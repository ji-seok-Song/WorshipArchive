import Foundation
import Observation
import SwiftData

actor PDFImportReservation {
    static let shared = PDFImportReservation()

    private var ownersByChecksum: [String: UUID] = [:]
    private var cancelledOwners: Set<UUID> = []

    func reserve(_ checksum: String, ownerID: UUID) -> Bool {
        guard !cancelledOwners.contains(ownerID) else { return false }
        if ownersByChecksum[checksum] == ownerID { return true }
        guard ownersByChecksum[checksum] == nil else { return false }

        ownersByChecksum[checksum] = ownerID
        return true
    }

    func cancel(ownerID: UUID) {
        cancelledOwners.insert(ownerID)
        ownersByChecksum = ownersByChecksum.filter { $0.value != ownerID }
    }

    func release(_ checksum: String, ownerID: UUID) {
        if ownersByChecksum[checksum] == ownerID {
            ownersByChecksum.removeValue(forKey: checksum)
        }
    }

    func finish(ownerID: UUID) {
        cancelledOwners.remove(ownerID)
    }
}

@MainActor
@Observable
final class PDFImportCoordinator {
    private struct PendingCandidate {
        let operationID: UUID
        let stagedPDF: StagedPDF
    }

    enum Phase: Equatable {
        case selecting
        case staging
        case analyzing
        case reviewing
        case saving
        case completed
    }

    private(set) var phase: Phase = .selecting
    private(set) var stagedPDF: StagedPDF?
    private(set) var analysisProgress: PDFAnalysisProgress?
    private(set) var analysisResult: PDFAnalysisResult?
    var drafts: [SongDraft] = []
    var errorMessage: String?

    @ObservationIgnored
    private let fileStore: any PDFFileStoring
    @ObservationIgnored
    private let pdfAnalyzer: any PDFAnalyzing
    @ObservationIgnored
    private weak var uploadScheduler: (any PDFAssetUploadScheduling)?
    @ObservationIgnored
    private let importReservation: PDFImportReservation
    @ObservationIgnored
    private var operationID: UUID?
    @ObservationIgnored
    private var activeAnalysisTask: Task<PDFAnalysisResult, Error>?
    @ObservationIgnored
    private var reservedChecksum: String?
    @ObservationIgnored
    private var reservationOwnerID: UUID?
    @ObservationIgnored
    private var pendingCandidate: PendingCandidate?

    init(
        fileStore: any PDFFileStoring,
        pdfAnalyzer: any PDFAnalyzing = LocalPDFAnalyzer(),
        importReservation: PDFImportReservation = .shared,
        uploadScheduler: (any PDFAssetUploadScheduling)? = nil
    ) {
        self.fileStore = fileStore
        self.pdfAnalyzer = pdfAnalyzer
        self.importReservation = importReservation
        self.uploadScheduler = uploadScheduler
    }

    var canSave: Bool {
        guard
            phase == .reviewing,
            let stagedPDF,
            let analysisResult,
            hasCompletePageAnalysis(analysisResult, pageCount: stagedPDF.pageCount)
        else {
            return false
        }

        return (try? SongDraftValidator.validate(
            drafts,
            documentPageCount: stagedPDF.pageCount
        )) != nil
    }

    var hasPendingImport: Bool {
        stagedPDF != nil
            || phase == .staging
            || phase == .analyzing
            || phase == .saving
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

        let supersededOperationID = operationID
        let supersededCandidate = pendingCandidate
        pendingCandidate = nil
        activeAnalysisTask?.cancel()
        activeAnalysisTask = nil

        let currentOperationID = UUID()
        operationID = currentOperationID
        defer {
            Task { [importReservation] in
                await importReservation.finish(ownerID: currentOperationID)
            }
        }

        let previousStagedPDF = stagedPDF
        let previousDrafts = drafts
        let previousAnalysisResult = analysisResult
        let previousChecksum = reservedChecksum
        let previousReservationOwnerID = reservationOwnerID
        var candidatePDF: StagedPDF?
        var didReserveCandidate = false

        phase = .staging
        analysisProgress = nil
        errorMessage = nil

        do {
            if let supersededOperationID {
                await importReservation.cancel(ownerID: supersededOperationID)
            }
            if let supersededCandidate {
                await fileStore.discard(supersededCandidate.stagedPDF)
            }
            guard operationID == currentOperationID else { return }

            let stagedPDF = try await fileStore.stagePDF(from: sourceURL)
            candidatePDF = stagedPDF

            guard operationID == currentOperationID else {
                await fileStore.discard(stagedPDF)
                return
            }
            pendingCandidate = PendingCandidate(
                operationID: currentOperationID,
                stagedPDF: stagedPDF
            )

            let context = ModelContext(modelContainer)
            try ensureDocumentIsNotDuplicate(
                checksum: stagedPDF.checksum,
                in: context
            )

            if stagedPDF.checksum != previousChecksum {
                let didReserve = await importReservation.reserve(
                    stagedPDF.checksum,
                    ownerID: currentOperationID
                )
                guard operationID == currentOperationID else {
                    if didReserve {
                        await importReservation.release(
                            stagedPDF.checksum,
                            ownerID: currentOperationID
                        )
                    }
                    await fileStore.discard(stagedPDF)
                    return
                }
                guard didReserve else {
                    throw PDFImportValidationError.duplicateImportInProgress
                }
                didReserveCandidate = true
            }

            guard operationID == currentOperationID else {
                await discardCandidate(
                    stagedPDF,
                    releasingReservation: didReserveCandidate,
                    ownerID: currentOperationID
                )
                return
            }

            let stagedURL = try await fileStore.stagedFileURL(for: stagedPDF)
            guard operationID == currentOperationID else {
                await discardCandidate(
                    stagedPDF,
                    releasingReservation: didReserveCandidate,
                    ownerID: currentOperationID
                )
                return
            }

            phase = .analyzing
            analysisProgress = PDFAnalysisProgress(
                stage: .extractingEmbeddedText,
                completedPageCount: 0,
                totalPageCount: stagedPDF.pageCount
            )

            let analysisTask = makeAnalysisTask(
                stagedPDF: stagedPDF,
                stagedURL: stagedURL,
                operationID: currentOperationID
            )
            activeAnalysisTask = analysisTask
            let result = try await analysisTask.value

            guard operationID == currentOperationID else {
                await discardCandidate(
                    stagedPDF,
                    releasingReservation: didReserveCandidate,
                    ownerID: currentOperationID
                )
                return
            }
            guard hasCompletePageAnalysis(result, pageCount: stagedPDF.pageCount) else {
                throw PDFImportValidationError.incompleteAnalysis
            }

            self.stagedPDF = stagedPDF
            reservedChecksum = stagedPDF.checksum
            reservationOwnerID = didReserveCandidate
                ? currentOperationID
                : previousReservationOwnerID
            pendingCandidate = nil
            analysisResult = result
            drafts = result.suggestions.map(songDraft(from:))
            activeAnalysisTask = nil
            analysisProgress = nil
            operationID = nil
            phase = .reviewing

            if let previousStagedPDF {
                await fileStore.discard(previousStagedPDF)
            }
            if
                let previousChecksum,
                let previousReservationOwnerID,
                previousChecksum != stagedPDF.checksum
            {
                await importReservation.release(
                    previousChecksum,
                    ownerID: previousReservationOwnerID
                )
            }
        } catch {
            if let candidatePDF {
                await discardCandidate(
                    candidatePDF,
                    releasingReservation: didReserveCandidate,
                    ownerID: currentOperationID
                )
            }

            guard operationID == currentOperationID else { return }

            pendingCandidate = nil
            self.stagedPDF = previousStagedPDF
            drafts = previousDrafts
            analysisResult = previousAnalysisResult
            analysisProgress = nil
            activeAnalysisTask = nil
            reservedChecksum = previousChecksum
            reservationOwnerID = previousReservationOwnerID
            operationID = nil
            phase = previousStagedPDF == nil ? .selecting : .reviewing
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func retryAnalysis() async {
        guard phase == .reviewing, let stagedPDF else { return }

        let previousDrafts = drafts
        let previousAnalysisResult = analysisResult
        let currentOperationID = UUID()
        operationID = currentOperationID
        defer {
            Task { [importReservation] in
                await importReservation.finish(ownerID: currentOperationID)
            }
        }
        phase = .analyzing
        errorMessage = nil
        analysisProgress = PDFAnalysisProgress(
            stage: .extractingEmbeddedText,
            completedPageCount: 0,
            totalPageCount: stagedPDF.pageCount
        )

        do {
            let stagedURL = try await fileStore.stagedFileURL(for: stagedPDF)
            guard operationID == currentOperationID else { return }

            let analysisTask = makeAnalysisTask(
                stagedPDF: stagedPDF,
                stagedURL: stagedURL,
                operationID: currentOperationID
            )
            activeAnalysisTask = analysisTask
            let result = try await analysisTask.value

            guard operationID == currentOperationID else { return }
            guard hasCompletePageAnalysis(result, pageCount: stagedPDF.pageCount) else {
                throw PDFImportValidationError.incompleteAnalysis
            }

            analysisResult = result
            drafts = result.suggestions.map(songDraft(from:))
            activeAnalysisTask = nil
            analysisProgress = nil
            operationID = nil
            phase = .reviewing
        } catch {
            guard operationID == currentOperationID else { return }

            drafts = previousDrafts
            analysisResult = previousAnalysisResult
            activeAnalysisTask = nil
            analysisProgress = nil
            operationID = nil
            phase = .reviewing
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addSongDraft() {
        guard let stagedPDF else { return }

        if let unusedPage = firstUnusedPage(upTo: stagedPDF.pageCount) {
            drafts.append(SongDraft(
                title: "새 찬양 \(drafts.count + 1)",
                startPageNumber: unusedPage,
                endPageNumber: unusedPage
            ))
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

        drafts.append(SongDraft(
            title: "새 찬양 \(drafts.count + 1)",
            startPageNumber: stagedPDF.pageCount,
            endPageNumber: stagedPDF.pageCount
        ))
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
        guard
            let analysisResult,
            hasCompletePageAnalysis(analysisResult, pageCount: stagedPDF.pageCount)
        else {
            errorMessage = PDFImportValidationError.incompleteAnalysis.localizedDescription
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
        var assetToUpload: LocalPDFAsset?

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
                analysisStatus: .completed
            )
            if analysisResult.failedPageCount > 0 {
                document.analysisErrorMessage = "\(analysisResult.failedPageCount)개 페이지는 글자 인식을 확인해 주세요."
            }
            context.insert(document)

            for page in analysisResult.pages {
                let pageAnalysis = try PageAnalysis.create(
                    pageIndex: page.pageIndex,
                    extractedText: page.text,
                    confidence: page.confidence,
                    status: page.status,
                    recognitionMethod: page.recognitionMethod,
                    document: document
                )
                pageAnalysis.errorMessage = page.errorMessage
                context.insert(pageAnalysis)
            }

            let pagesByIndex = Dictionary(
                uniqueKeysWithValues: analysisResult.pages.map { ($0.pageIndex, $0) }
            )
            for draft in validatedDrafts {
                let recognizedText = (draft.pageRange.startPageIndex...draft.pageRange.endPageIndex)
                    .compactMap { pagesByIndex[$0]?.text }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                let song = Song(title: draft.title, lyricsText: recognizedText)
                let sheet = try SongSheet.create(
                    startPageIndex: draft.pageRange.startPageIndex,
                    endPageIndex: draft.pageRange.endPageIndex,
                    musicalKey: draft.musicalKey,
                    recognizedText: recognizedText,
                    document: document,
                    song: song
                )
                context.insert(song)
                context.insert(sheet)
            }

            try context.save()
            assetToUpload = LocalPDFAsset(
                documentID: document.id,
                storedFileName: storedPDF.storedFileName,
                checksum: storedPDF.checksum,
                fileSize: storedPDF.fileSize,
                pageCount: storedPDF.pageCount
            )
            await fileStore.discard(stagedPDF)
            await releaseReservation()
            self.stagedPDF = nil
            drafts = []
            self.analysisResult = nil
            analysisProgress = nil
            phase = .completed
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

        // The local database and original PDF are already committed here.
        // Cloud enqueue/upload failures must never enter the rollback path above.
        if let assetToUpload {
            await uploadScheduler?.enqueueForUpload(assetToUpload)
        }
        return true
    }

    func cancel() async {
        guard phase != .saving else { return }

        let cancelledOperationID = operationID
        let pendingCandidate = self.pendingCandidate
        operationID = nil
        self.pendingCandidate = nil
        activeAnalysisTask?.cancel()
        activeAnalysisTask = nil

        let stagedPDF = self.stagedPDF
        let reservedChecksum = self.reservedChecksum
        let reservationOwnerID = self.reservationOwnerID
        self.stagedPDF = nil
        self.reservedChecksum = nil
        self.reservationOwnerID = nil
        drafts = []
        analysisResult = nil
        analysisProgress = nil
        phase = .selecting

        if let cancelledOperationID {
            await importReservation.cancel(ownerID: cancelledOperationID)
        }
        if let pendingCandidate {
            await fileStore.discard(pendingCandidate.stagedPDF)
        }
        if let stagedPDF {
            await fileStore.discard(stagedPDF)
        }
        if let reservedChecksum, let reservationOwnerID {
            await importReservation.release(
                reservedChecksum,
                ownerID: reservationOwnerID
            )
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func makeAnalysisTask(
        stagedPDF: StagedPDF,
        stagedURL: URL,
        operationID: UUID
    ) -> Task<PDFAnalysisResult, Error> {
        Task { [pdfAnalyzer] in
            try await pdfAnalyzer.analyze(
                pdfAt: stagedURL,
                originalFileName: stagedPDF.originalFileName,
                expectedPageCount: stagedPDF.pageCount
            ) { [weak self] progress in
                await self?.apply(progress: progress, operationID: operationID)
            }
        }
    }

    private func apply(
        progress: PDFAnalysisProgress,
        operationID: UUID
    ) {
        guard self.operationID == operationID, phase == .analyzing else { return }
        analysisProgress = progress
    }

    private func songDraft(from suggestion: SongDraftSuggestion) -> SongDraft {
        SongDraft(
            title: suggestion.title,
            startPageNumber: suggestion.startPageNumber,
            endPageNumber: suggestion.endPageNumber,
            suggestionConfidence: suggestion.confidence
        )
    }

    private func discardCandidate(
        _ stagedPDF: StagedPDF,
        releasingReservation: Bool,
        ownerID: UUID? = nil
    ) async {
        if releasingReservation, let ownerID {
            await importReservation.release(
                stagedPDF.checksum,
                ownerID: ownerID
            )
        }
        await fileStore.discard(stagedPDF)
    }

    private func hasCompletePageAnalysis(
        _ result: PDFAnalysisResult,
        pageCount: Int
    ) -> Bool {
        result.pages.map(\.pageIndex).sorted() == Array(0..<pageCount)
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
        guard let reservedChecksum, let reservationOwnerID else { return }
        self.reservedChecksum = nil
        self.reservationOwnerID = nil
        await importReservation.release(
            reservedChecksum,
            ownerID: reservationOwnerID
        )
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
