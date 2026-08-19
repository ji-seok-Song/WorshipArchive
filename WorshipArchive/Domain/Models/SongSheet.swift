import Foundation
import SwiftData

@Model
final class SongSheet {
    var id: UUID = UUID()
    private(set) var startPageIndex: Int = 0
    private(set) var endPageIndex: Int = 0
    var keyRawValue: String = ""
    var recognizedText: String = ""
    var createdAt: Date = Date()
    private(set) var lastViewedPageIndex: Int = 0
    var lastOpenedAt: Date?
    var document: ArchiveDocument?
    var song: Song?

    private init(
        id: UUID = UUID(),
        pageRange: SheetPageRange,
        musicalKey: MusicalKey? = nil,
        recognizedText: String = "",
        createdAt: Date = Date(),
        document: ArchiveDocument,
        song: Song
    ) {
        self.id = id
        startPageIndex = pageRange.startPageIndex
        endPageIndex = pageRange.endPageIndex
        keyRawValue = musicalKey?.rawValue ?? ""
        self.recognizedText = recognizedText
        self.createdAt = createdAt
        lastViewedPageIndex = pageRange.startPageIndex
        self.document = document
        self.song = song
    }

    static func create(
        id: UUID = UUID(),
        startPageIndex: Int,
        endPageIndex: Int,
        musicalKey: MusicalKey? = nil,
        recognizedText: String = "",
        createdAt: Date = Date(),
        document: ArchiveDocument,
        song: Song
    ) throws -> SongSheet {
        let pageRange = try SheetPageRange(
            startPageIndex: startPageIndex,
            endPageIndex: endPageIndex,
            documentPageCount: document.pageCount
        )

        return SongSheet(
            id: id,
            pageRange: pageRange,
            musicalKey: musicalKey,
            recognizedText: recognizedText,
            createdAt: createdAt,
            document: document,
            song: song
        )
    }

    var musicalKey: MusicalKey? {
        get { MusicalKey(rawValue: keyRawValue) }
        set { keyRawValue = newValue?.rawValue ?? "" }
    }

    var pageCount: Int {
        endPageIndex - startPageIndex + 1
    }

    func updatePageRange(
        startPageIndex: Int,
        endPageIndex: Int
    ) throws {
        guard let document else {
            throw PageRangeValidationError.missingDocument
        }

        let pageRange = try SheetPageRange(
            startPageIndex: startPageIndex,
            endPageIndex: endPageIndex,
            documentPageCount: document.pageCount
        )

        self.startPageIndex = pageRange.startPageIndex
        self.endPageIndex = pageRange.endPageIndex
        lastViewedPageIndex = pageRange.clamped(lastViewedPageIndex)
    }

    func updateLastViewedPageIndex(_ pageIndex: Int) {
        let pageRange = try? SheetPageRange(
            startPageIndex: startPageIndex,
            endPageIndex: endPageIndex,
            documentPageCount: document?.pageCount ?? 0
        )
        lastViewedPageIndex = pageRange?.clamped(pageIndex) ?? startPageIndex
    }
}
