import Foundation

struct SongDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var musicalKey: MusicalKey?
    var startPageNumber: Int
    var endPageNumber: Int

    init(
        id: UUID = UUID(),
        title: String,
        musicalKey: MusicalKey? = nil,
        startPageNumber: Int,
        endPageNumber: Int
    ) {
        self.id = id
        self.title = title
        self.musicalKey = musicalKey
        self.startPageNumber = startPageNumber
        self.endPageNumber = endPageNumber
    }
}

struct ValidatedSongDraft {
    let title: String
    let musicalKey: MusicalKey?
    let pageRange: SheetPageRange
}

enum SongDraftValidator {
    static func validate(
        _ drafts: [SongDraft],
        documentPageCount: Int
    ) throws -> [ValidatedSongDraft] {
        guard !drafts.isEmpty else {
            throw PDFImportValidationError.noSongs
        }
        guard documentPageCount > 0 else {
            throw PageRangeValidationError.emptyDocument
        }

        let validatedDrafts = try drafts.map { draft in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw PDFImportValidationError.emptyTitle
            }
            guard
                (1...documentPageCount).contains(draft.startPageNumber),
                (1...documentPageCount).contains(draft.endPageNumber)
            else {
                throw PageRangeValidationError.pageOutsideDocument
            }
            guard draft.startPageNumber <= draft.endPageNumber else {
                throw PageRangeValidationError.reversedRange
            }

            let pageRange = try SheetPageRange(
                startPageIndex: draft.startPageNumber - 1,
                endPageIndex: draft.endPageNumber - 1,
                documentPageCount: documentPageCount
            )

            return ValidatedSongDraft(
                title: title,
                musicalKey: draft.musicalKey,
                pageRange: pageRange
            )
        }

        let sortedRanges = validatedDrafts
            .map(\.pageRange)
            .sorted { lhs, rhs in
                lhs.startPageIndex < rhs.startPageIndex
            }

        for index in sortedRanges.indices.dropFirst() {
            let previousRange = sortedRanges[index - 1]
            let currentRange = sortedRanges[index]
            guard currentRange.startPageIndex >= previousRange.endPageIndex else {
                throw PDFImportValidationError.overlappingPages
            }
        }

        return validatedDrafts
    }
}

enum PDFImportValidationError: LocalizedError, Equatable {
    case noSongs
    case emptyTitle
    case overlappingPages
    case duplicateDocument(String)
    case duplicateImportInProgress
    case missingStagedPDF

    var errorDescription: String? {
        switch self {
        case .noSongs:
            "한 곡 이상 추가해 주세요."
        case .emptyTitle:
            "모든 곡의 제목을 입력해 주세요."
        case .overlappingPages:
            "곡의 페이지 범위가 두 페이지 이상 겹치지 않게 조정해 주세요."
        case .duplicateDocument(let fileName):
            "같은 내용의 PDF ‘\(fileName)’이 이미 보관되어 있습니다."
        case .duplicateImportInProgress:
            "같은 내용의 PDF를 다른 창에서 가져오는 중입니다."
        case .missingStagedPDF:
            "저장할 PDF를 찾을 수 없습니다. 다시 선택해 주세요."
        }
    }
}
