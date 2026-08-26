import Foundation
import SwiftData

@MainActor
enum ArchiveLibraryEditing {
    static func updateSong(
        _ song: Song,
        title: String,
        notes: String,
        in context: ModelContext
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw ArchiveEditingError.emptyTitle }

        song.rename(to: trimmedTitle)
        song.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    static func updateSheet(
        _ sheet: SongSheet,
        musicalKey: MusicalKey?,
        startPageNumber: Int,
        endPageNumber: Int,
        in context: ModelContext
    ) throws {
        try sheet.updatePageRange(
            startPageIndex: startPageNumber - 1,
            endPageIndex: endPageNumber - 1
        )
        sheet.musicalKey = musicalKey
        sheet.recognizedText = recognizedText(for: sheet)
        try context.save()
    }

    static func updateSheetKey(
        _ sheet: SongSheet,
        musicalKey: MusicalKey?,
        in context: ModelContext
    ) throws {
        let previousKey = sheet.musicalKey
        sheet.musicalKey = musicalKey

        do {
            try context.save()
        } catch {
            sheet.musicalKey = previousKey
            throw error
        }
    }

    static func deleteSheet(_ sheet: SongSheet, in context: ModelContext) throws {
        context.delete(sheet)
        try context.save()
    }

    static func deleteSong(_ song: Song, in context: ModelContext) throws {
        context.delete(song)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func mergeSong(
        _ source: Song,
        into target: Song,
        in context: ModelContext
    ) throws {
        guard source.id != target.id else { throw ArchiveEditingError.sameSong }

        let movedSheets = source.sheets ?? []

        for sheet in movedSheets {
            sheet.song = target
        }

        target.isFavorite = target.isFavorite || source.isFavorite
        target.notes = combinedText(target.notes, source.notes)
        context.delete(source)
        try context.save()
    }

    static func deleteDocument(
        _ document: ArchiveDocument,
        in context: ModelContext
    ) throws -> String {
        var affectedSongs: [UUID: Song] = [:]
        for song in (document.sheets ?? []).compactMap(\.song) {
            affectedSongs[song.id] = song
        }
        for song in affectedSongs.values {
            let remainingSheets = (song.sheets ?? []).filter {
                $0.document?.id != document.id
            }
            if remainingSheets.isEmpty {
                context.delete(song)
            }
        }

        let storedFileName = document.storedFileName
        context.delete(document)
        try context.save()
        return storedFileName
    }

    private static func recognizedText(for sheet: SongSheet) -> String {
        guard let document = sheet.document else { return sheet.recognizedText }
        return (document.pageAnalyses ?? [])
            .filter {
                ($0.pageIndex >= sheet.startPageIndex)
                    && ($0.pageIndex <= sheet.endPageIndex)
            }
            .sorted { $0.pageIndex < $1.pageIndex }
            .map(\.extractedText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func combinedText(_ first: String, _ second: String) -> String {
        [first, second]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { values, value in
                if !values.contains(value) { values.append(value) }
            }
            .joined(separator: "\n\n")
    }
}

enum ArchiveEditingError: LocalizedError, Equatable {
    case emptyTitle
    case sameSong

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "곡 제목을 입력해 주세요."
        case .sameSong:
            "같은 곡끼리는 병합할 수 없습니다."
        }
    }
}
