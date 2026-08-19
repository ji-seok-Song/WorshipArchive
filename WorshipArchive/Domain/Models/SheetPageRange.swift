import Foundation

struct SheetPageRange: Equatable, Sendable {
    let startPageIndex: Int
    let endPageIndex: Int

    init(
        startPageIndex: Int,
        endPageIndex: Int,
        documentPageCount: Int
    ) throws {
        guard documentPageCount > 0 else {
            throw PageRangeValidationError.emptyDocument
        }
        guard startPageIndex >= 0 else {
            throw PageRangeValidationError.negativeStartPage
        }
        guard startPageIndex <= endPageIndex else {
            throw PageRangeValidationError.reversedRange
        }
        guard endPageIndex < documentPageCount else {
            throw PageRangeValidationError.pageOutsideDocument
        }

        self.startPageIndex = startPageIndex
        self.endPageIndex = endPageIndex
    }

    var pageCount: Int {
        endPageIndex - startPageIndex + 1
    }

    func contains(_ pageIndex: Int) -> Bool {
        startPageIndex...endPageIndex ~= pageIndex
    }

    func clamped(_ pageIndex: Int) -> Int {
        min(max(pageIndex, startPageIndex), endPageIndex)
    }
}

enum PageRangeValidationError: LocalizedError, Equatable {
    case emptyDocument
    case negativeStartPage
    case reversedRange
    case pageOutsideDocument
    case missingDocument

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            "페이지가 없는 PDF에는 곡 범위를 만들 수 없습니다."
        case .negativeStartPage:
            "시작 페이지는 1페이지 이상이어야 합니다."
        case .reversedRange:
            "마지막 페이지는 시작 페이지보다 앞설 수 없습니다."
        case .pageOutsideDocument:
            "곡 범위가 PDF의 전체 페이지를 벗어났습니다."
        case .missingDocument:
            "연결된 원본 PDF를 찾을 수 없습니다."
        }
    }
}

enum PageIndexValidator {
    static func validate(_ pageIndex: Int, documentPageCount: Int) throws {
        guard documentPageCount > 0 else {
            throw PageRangeValidationError.emptyDocument
        }
        guard pageIndex >= 0 else {
            throw PageRangeValidationError.negativeStartPage
        }
        guard pageIndex < documentPageCount else {
            throw PageRangeValidationError.pageOutsideDocument
        }
    }
}
