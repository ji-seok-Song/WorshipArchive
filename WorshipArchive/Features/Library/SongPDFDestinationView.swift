import SwiftUI

struct SongPDFDestinationView: View {
    let song: Song
    let fileAccess: any StoredPDFAccessing

    var body: some View {
        if
            let sheet = PreferredSongSheetSelector.select(for: song),
            let document = sheet.document
        {
            PDFViewerView(
                document: document,
                sheet: sheet,
                fileAccess: fileAccess
            )
        } else {
            ContentUnavailableView {
                Label("연결된 악보가 없어요", systemImage: "doc.questionmark")
            } description: {
                Text("이 곡에 연결된 PDF 페이지를 찾을 수 없습니다.")
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@MainActor
enum PreferredSongSheetSelector {
    static func select(for song: Song) -> SongSheet? {
        (song.sheets ?? [])
            .filter(isOpenable)
            .sorted(by: isPreferred)
            .first
    }

    private static func isOpenable(_ sheet: SongSheet) -> Bool {
        guard let document = sheet.document else { return false }
        return document.pageCount > 0
            && sheet.startPageIndex >= 0
            && sheet.startPageIndex <= sheet.endPageIndex
            && sheet.endPageIndex < document.pageCount
    }

    private static func isPreferred(_ lhs: SongSheet, _ rhs: SongSheet) -> Bool {
        switch (lhs.lastOpenedAt, rhs.lastOpenedAt) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
