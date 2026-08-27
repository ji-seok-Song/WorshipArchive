import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SongDetailViewModel {
    var favoriteSaveErrorMessage: String?
    var showsSongEditor = false
    var showsSongMergeForm = false
    var sheetBeingEdited: SongSheet?
    var sheetPendingDeletion: SongSheet?
    var showsSongDeleteConfirmation = false
    var archiveEditErrorMessage: String?

    func sortedSheets(for song: Song) -> [SongSheet] {
        (song.sheets ?? []).sorted { lhs, rhs in
            let lhsName = lhs.document?.originalFileName ?? ""
            let rhsName = rhs.document?.originalFileName ?? ""
            if lhsName != rhsName {
                return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
            }
            if lhs.startPageIndex != rhs.startPageIndex {
                return lhs.startPageIndex < rhs.startPageIndex
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func toggleFavorite(for song: Song, in modelContext: ModelContext) {
        let previousValue = song.isFavorite
        song.isFavorite.toggle()

        do {
            try modelContext.save()
        } catch {
            song.isFavorite = previousValue
            favoriteSaveErrorMessage = error.localizedDescription
        }
    }

    func delete(_ sheet: SongSheet, in modelContext: ModelContext) {
        do {
            try ArchiveLibraryEditing.deleteSheet(sheet, in: modelContext)
            sheetPendingDeletion = nil
        } catch {
            sheetPendingDeletion = nil
            archiveEditErrorMessage = error.localizedDescription
        }
    }

    func delete(_ song: Song, in modelContext: ModelContext) -> Bool {
        do {
            try ArchiveLibraryEditing.deleteSong(song, in: modelContext)
            return true
        } catch {
            archiveEditErrorMessage = error.localizedDescription
            return false
        }
    }
}

@MainActor
@Observable
final class SongMergeViewModel {
    let sourceSong: Song
    var targetSongID: UUID?
    var errorMessage: String?

    init(sourceSong: Song) {
        self.sourceSong = sourceSong
    }

    func targetSongs(from songs: [Song]) -> [Song] {
        songs.filter { $0.id != sourceSong.id }
    }

    func merge(into songs: [Song], in modelContext: ModelContext) -> Bool {
        guard
            let targetSongID,
            let target = targetSongs(from: songs).first(where: { $0.id == targetSongID })
        else {
            return false
        }

        do {
            try ArchiveLibraryEditing.mergeSong(
                sourceSong,
                into: target,
                in: modelContext
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

@MainActor
@Observable
final class SongEditViewModel {
    let song: Song
    var title: String
    var notes: String
    var errorMessage: String?

    init(song: Song) {
        self.song = song
        title = song.title
        notes = song.notes
    }

    func save(in modelContext: ModelContext) -> Bool {
        do {
            try ArchiveLibraryEditing.updateSong(
                song,
                title: title,
                notes: notes,
                in: modelContext
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

@MainActor
@Observable
final class SongSheetEditViewModel {
    let sheet: SongSheet
    var musicalKey: MusicalKey?
    var startPageNumber: Int
    var endPageNumber: Int
    var errorMessage: String?

    init(sheet: SongSheet) {
        self.sheet = sheet
        musicalKey = sheet.musicalKey
        startPageNumber = sheet.startPageIndex + 1
        endPageNumber = sheet.endPageIndex + 1
    }

    var pageCount: Int {
        max(sheet.document?.pageCount ?? 1, 1)
    }

    func save(in modelContext: ModelContext) -> Bool {
        do {
            try ArchiveLibraryEditing.updateSheet(
                sheet,
                musicalKey: musicalKey,
                startPageNumber: startPageNumber,
                endPageNumber: endPageNumber,
                in: modelContext
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
