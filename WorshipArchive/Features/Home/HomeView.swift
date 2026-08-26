import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var songs: [Song]
    @Query private var sheets: [SongSheet]

    let fileAccess: any StoredPDFAccessing
    let navigate: (AppDestination) -> Void
    let addPDF: () -> Void

    init(
        fileAccess: any StoredPDFAccessing = LocalPDFFileStore.live(),
        navigate: @escaping (AppDestination) -> Void,
        addPDF: @escaping () -> Void
    ) {
        self.fileAccess = fileAccess
        self.navigate = navigate
        self.addPDF = addPDF
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                welcomeCard

                VStack(alignment: .leading, spacing: 12) {
                    Text("빠른 이동")
                        .font(.title3.bold())

                    LazyVGrid(columns: columns, spacing: 12) {
                        QuickLinkCard(
                            title: "전체 라이브러리",
                            subtitle: "곡과 원본 PDF를 한곳에서 관리하세요.",
                            systemImage: "books.vertical",
                            tint: ArchiveTheme.accent
                        ) {
                            navigate(.library)
                        }
                        
                        QuickLinkCard(
                            title: "악보 검색",
                            subtitle: "곡 제목이나 원본 PDF 이름으로 찾아보세요.",
                            systemImage: "text.magnifyingglass",
                            tint: ArchiveTheme.tint
                        ) {
                            navigate(.search)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("최근 본 악보")
                            .font(.title3.bold())

                        Spacer()

                        if !recentScores.isEmpty {
                            Button("전체 보기") {
                                navigate(.library)
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }

                    if recentScores.isEmpty {
                        ArchiveEmptyState(
                            systemImage: "clock.arrow.circlepath",
                            title: "아직 열어본 악보가 없어요",
                            message: "PDF를 등록하고 곡을 열면 최근 항목에서 바로 이어볼 수 있어요.",
                            isCompact: true
                        )
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(recentScores) { entry in
                                RecentScoreRow(
                                    entry: entry,
                                    fileAccess: fileAccess
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal)
            .padding(.bottom, 104)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchiveTheme.background)
        .navigationTitle("찬양서랍")
    }

    private var recentScores: [RecentScoreEntry] {
        RecentScoreListing.entries(
            songs: songs,
            sheets: sheets
        )
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text("기억나는 단서만으로\n다시 찾는 나의 찬양 악보")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("여러 곡이 담긴 PDF도 한 번만 올리면 곡별로 정리할 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: addPDF) {
                Label("PDF 추가", systemImage: "doc.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(ArchiveTheme.tint)
            .accessibilityHint("파일 앱에서 찬양 악보 PDF를 선택합니다")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            LinearGradient(
                colors: [ArchiveTheme.tint, ArchiveTheme.tint.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 24)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct RecentScoreRow: View {
    let entry: RecentScoreEntry
    let fileAccess: any StoredPDFAccessing

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                PDFViewerView(
                    document: entry.document,
                    sheet: entry.sheet,
                    fileAccess: fileAccess
                )
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ArchiveTheme.tint)
                        .frame(width: 44, height: 44)
                        .background(
                            ArchiveTheme.tint.opacity(0.12),
                            in: .rect(cornerRadius: 12)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.song.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(entry.scoreSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(entry.openedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .contentShape(.rect)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(entry.song.title)
                .accessibilityValue(entry.scoreSummary)
                .accessibilityHint("마지막으로 본 페이지부터 악보를 엽니다")
            }
            .buttonStyle(.plain)
        }
        .background(ArchiveTheme.surface, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        HomeView(navigate: { _ in }, addPDF: {})
    }
    .modelContainer(AppModelContainer.preview)
}
