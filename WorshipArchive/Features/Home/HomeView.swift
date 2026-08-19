import SwiftUI

struct HomeView: View {
    let navigate: (AppDestination) -> Void

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
                            title: "악보 검색",
                            subtitle: "기억나는 제목이나 가사로 찾아보세요.",
                            systemImage: "text.magnifyingglass",
                            tint: ArchiveTheme.tint
                        ) {
                            navigate(.search)
                        }

                        QuickLinkCard(
                            title: "전체 라이브러리",
                            subtitle: "곡과 원본 PDF를 한곳에서 관리하세요.",
                            systemImage: "books.vertical",
                            tint: ArchiveTheme.accent
                        ) {
                            navigate(.library)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("최근 본 악보")
                        .font(.title3.bold())

                    ArchiveEmptyState(
                        systemImage: "clock.arrow.circlepath",
                        title: "아직 열어본 악보가 없어요",
                        message: "PDF를 등록하고 곡을 열면 최근 항목에서 바로 이어볼 수 있어요."
                    )
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(ArchiveTheme.background)
        .navigationTitle("찬양서랍")
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

            Label("첫 PDF를 추가하면 곡별 정리가 시작돼요", systemImage: "doc.badge.plus")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
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

#Preview {
    NavigationStack {
        HomeView(navigate: { _ in })
    }
}
